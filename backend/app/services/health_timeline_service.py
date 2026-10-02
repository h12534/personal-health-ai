from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.diet_coach import DietAdjustment
from app.models.health_activity import SleepLog, StepLog
from app.models.health_knowledge import LabReport, LabResult
from app.models.meal import MealLog
from app.models.supervision import HealthReport
from app.models.training import ExercisePR, TrainingAdjustment, WorkoutSession
from app.models.weight_log import WeightLog
from app.schemas.supervision import CrossDomainRead, TimelineEventRead
from app.services.daily_nutrition_service import DailyNutritionService


class CorrelationGuard:
    DISCLAIMER = "这些序列只用于观察同期变化；相关不等于因果，个人时间序列不能单独确认因果关系。"

    @classmethod
    def answer_causality_question(cls, question: str) -> str:
        del question
        return (
            "这些变化可能存在相关，但单凭个人时间序列不能确认因果。"
            "还可能受到饮食、用药、测量误差、睡眠、活动和时间等因素影响。"
        )


class HealthTimelineService:
    CATEGORY_TYPES = {
        "body": {"weight", "waist", "body_photo"},
        "nutrition": {"meal", "diet_adjustment"},
        "training": {"workout", "pr", "training_adjustment"},
        "lab": {"lab"},
        "report": {"health_report"},
    }

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.nutrition = DailyNutritionService(session)

    async def list_events(
        self,
        user_id: UUID,
        date_from: date,
        date_to: date,
        category: str = "all",
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[TimelineEventRead]:
        if date_to < date_from or (date_to - date_from).days > 730:
            raise AppError("invalid_timeline_range", "Timeline range is invalid or too large.", 422)
        timezone = await self.nutrition.timezone(user_id)
        start, end = self.nutrition._utc_bounds(date_from, date_to, timezone)
        events: list[TimelineEventRead] = []

        weights = (
            await self.session.scalars(
                select(WeightLog).where(
                    WeightLog.user_id == user_id,
                    WeightLog.measured_on >= date_from,
                    WeightLog.measured_on <= date_to,
                    WeightLog.deleted_at.is_(None),
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"weight:{item.id}",
                event_type="weight",
                category="body",
                occurred_at=datetime.combine(item.measured_on, time(8), timezone).astimezone(UTC),
                title="体重记录",
                summary=f"{float(item.weight_kg):.1f} kg",
                metadata={"weight_kg": float(item.weight_kg), "source": item.source},
            )
            for item in weights
        )
        meals = (
            await self.session.scalars(
                select(MealLog).where(
                    MealLog.user_id == user_id,
                    MealLog.eaten_at >= start,
                    MealLog.eaten_at < end,
                    MealLog.deleted_at.is_(None),
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"meal:{item.id}",
                event_type="meal",
                category="nutrition",
                occurred_at=self._aware(item.eaten_at),
                title={"breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐"}.get(
                    item.meal_type, "饮食记录"
                ),
                summary=f"约 {float(item.total_calories):.0f} kcal",
                metadata={"meal_type": item.meal_type, "protein_g": float(item.total_protein)},
            )
            for item in meals
        )
        workouts = (
            await self.session.scalars(
                select(WorkoutSession).where(
                    WorkoutSession.user_id == user_id,
                    WorkoutSession.started_at >= start,
                    WorkoutSession.started_at < end,
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"workout:{item.id}",
                event_type="workout",
                category="training",
                occurred_at=self._aware(item.started_at),
                title="训练" if item.status == "completed" else "训练记录",
                summary=(
                    f"已完成 · {item.duration_min} 分钟"
                    if item.status == "completed" and item.duration_min
                    else item.status
                ),
                metadata={"status": item.status, "duration_min": item.duration_min},
            )
            for item in workouts
        )
        prs = (
            await self.session.scalars(
                select(ExercisePR).where(
                    ExercisePR.user_id == user_id,
                    ExercisePR.achieved_at >= start,
                    ExercisePR.achieved_at < end,
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"pr:{item.id}",
                event_type="pr",
                category="training",
                occurred_at=self._aware(item.achieved_at),
                title="训练 PR",
                summary=f"{item.pr_type} · {float(item.value):g}",
                metadata={"exercise_id": str(item.exercise_id), "pr_type": item.pr_type},
            )
            for item in prs
        )
        steps = (
            await self.session.scalars(
                select(StepLog).where(
                    StepLog.user_id == user_id,
                    StepLog.step_date >= date_from,
                    StepLog.step_date <= date_to,
                    StepLog.steps.is_not(None),
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"steps:{item.id}",
                event_type="steps",
                category="body",
                occurred_at=datetime.combine(item.step_date, time(20), timezone).astimezone(UTC),
                title="步数",
                summary=f"{item.steps} 步",
                metadata={"steps": item.steps, "source": item.source},
            )
            for item in steps
        )
        sleeps = (
            await self.session.scalars(
                select(SleepLog).where(
                    SleepLog.user_id == user_id,
                    SleepLog.sleep_end >= start - timedelta(hours=12),
                    SleepLog.sleep_end < end,
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"sleep:{item.id}",
                event_type="sleep",
                category="body",
                occurred_at=self._aware(item.sleep_end),
                title="睡眠",
                summary=f"{item.duration_min / 60:.1f} 小时",
                metadata={"duration_min": item.duration_min, "source": item.source},
            )
            for item in sleeps
        )
        labs = (
            await self.session.scalars(
                select(LabReport).where(
                    LabReport.user_id == user_id,
                    LabReport.report_date >= date_from,
                    LabReport.report_date <= date_to,
                    LabReport.review_status == "confirmed",
                    LabReport.deleted_at.is_(None),
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"lab:{item.id}",
                event_type="lab",
                category="lab",
                occurred_at=datetime.combine(item.report_date, time(10), timezone).astimezone(UTC),
                title="体检报告",
                summary=f"已确认 {len([r for r in item.results if r.deleted_at is None])} 项指标",
                metadata={"report_id": str(item.id)},
            )
            for item in labs
        )
        diet_adjustments = (
            await self.session.scalars(
                select(DietAdjustment).where(
                    DietAdjustment.user_id == user_id,
                    DietAdjustment.created_at >= start,
                    DietAdjustment.created_at < end,
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"diet-adjustment:{item.id}",
                event_type="diet_adjustment",
                category="nutrition",
                occurred_at=self._aware(item.created_at),
                title="饮食目标调整",
                summary=item.reason,
                metadata={"status": item.status},
            )
            for item in diet_adjustments
        )
        training_adjustments = (
            await self.session.scalars(
                select(TrainingAdjustment).where(
                    TrainingAdjustment.user_id == user_id,
                    TrainingAdjustment.created_at >= start,
                    TrainingAdjustment.created_at < end,
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"training-adjustment:{item.id}",
                event_type="training_adjustment",
                category="training",
                occurred_at=self._aware(item.created_at),
                title="训练调整",
                summary=item.reason,
                metadata={"status": item.status},
            )
            for item in training_adjustments
        )
        reports = (
            await self.session.scalars(
                select(HealthReport).where(
                    HealthReport.user_id == user_id,
                    HealthReport.period_end >= date_from,
                    HealthReport.period_end <= date_to,
                )
            )
        ).all()
        events.extend(
            TimelineEventRead(
                id=f"health-report:{item.id}",
                event_type="health_report",
                category="report",
                occurred_at=self._aware(item.created_at),
                title={"daily": "每日报告", "weekly": "每周报告", "monthly": "每月报告"}.get(
                    item.report_type, "健康报告"
                ),
                summary=item.summary,
                metadata={"report_id": str(item.id), "report_type": item.report_type},
            )
            for item in reports
        )
        if category != "all":
            allowed = self.CATEGORY_TYPES.get(category)
            if allowed is None:
                raise AppError("invalid_timeline_category", "Unknown timeline category.", 422)
            events = [item for item in events if item.event_type in allowed]
        ordered = sorted(events, key=lambda item: item.occurred_at, reverse=True)
        return ordered[offset : offset + limit]

    async def cross_domain(
        self, user_id: UUID, date_from: date, date_to: date, metrics: list[str]
    ) -> CrossDomainRead:
        allowed = {"weight", "steps", "sleep", "hba1c"}
        selected: list[str] = list(dict.fromkeys(metrics))
        if not selected or any(item not in allowed for item in selected):
            raise AppError("invalid_cross_domain_metrics", "Unsupported trend metric.", 422)
        if len(selected) > 4 or date_to < date_from or (date_to - date_from).days > 730:
            raise AppError("invalid_cross_domain_range", "Trend range is invalid.", 422)
        series: dict[str, list[dict[str, object]]] = {item: [] for item in selected}
        if "weight" in series:
            weight_values = (
                await self.session.scalars(
                    select(WeightLog).where(
                        WeightLog.user_id == user_id,
                        WeightLog.measured_on >= date_from,
                        WeightLog.measured_on <= date_to,
                        WeightLog.deleted_at.is_(None),
                    )
                )
            ).all()
            series["weight"] = [
                {"date": item.measured_on.isoformat(), "value": float(item.weight_kg), "unit": "kg"}
                for item in weight_values
            ]
        if "steps" in series:
            step_values = (
                await self.session.scalars(
                    select(StepLog).where(
                        StepLog.user_id == user_id,
                        StepLog.step_date >= date_from,
                        StepLog.step_date <= date_to,
                        StepLog.steps.is_not(None),
                    )
                )
            ).all()
            series["steps"] = [
                {"date": item.step_date.isoformat(), "value": item.steps, "unit": "steps"}
                for item in step_values
            ]
        if "sleep" in series:
            timezone = await self.nutrition.timezone(user_id)
            start, end = self.nutrition._utc_bounds(date_from, date_to, timezone)
            sleep_values = (
                await self.session.scalars(
                    select(SleepLog).where(
                        SleepLog.user_id == user_id,
                        SleepLog.sleep_end >= start - timedelta(hours=12),
                        SleepLog.sleep_end < end,
                    )
                )
            ).all()
            series["sleep"] = [
                {
                    "date": self._aware(item.sleep_end).astimezone(timezone).date().isoformat(),
                    "value": round(item.duration_min / 60, 2),
                    "unit": "hours",
                }
                for item in sleep_values
            ]
        if "hba1c" in series:
            hba1c_values = (
                await self.session.execute(
                    select(LabReport.report_date, LabResult.value_numeric, LabResult.unit)
                    .join(LabResult, LabResult.report_id == LabReport.id)
                    .where(
                        LabReport.user_id == user_id,
                        LabReport.report_date >= date_from,
                        LabReport.report_date <= date_to,
                        LabReport.review_status == "confirmed",
                        LabReport.deleted_at.is_(None),
                        LabResult.normalized_name == "HBA1C",
                        LabResult.user_confirmed.is_(True),
                        LabResult.deleted_at.is_(None),
                    )
                )
            ).all()
            series["hba1c"] = [
                {"date": item[0].isoformat(), "value": float(item[1]), "unit": item[2] or "%"}
                for item in hba1c_values
                if item[1] is not None
            ]
        observations = [
            f"{key} 在所选区间有 {len(points)} 个数据点。" for key, points in series.items()
        ]
        return CrossDomainRead(
            date_from=date_from,
            date_to=date_to,
            series=series,
            observations=observations,
            disclaimer=CorrelationGuard.DISCLAIMER,
        )

    @staticmethod
    def _aware(value: datetime) -> datetime:
        return value if value.tzinfo else value.replace(tzinfo=UTC)
