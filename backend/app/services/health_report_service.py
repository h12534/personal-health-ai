from __future__ import annotations

import hashlib
import json
from datetime import UTC, date, datetime, time, timedelta
from time import perf_counter
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError
from app.models.health_activity import RecoverySnapshot, SleepLog, StepLog
from app.models.health_knowledge import LabReport
from app.models.meal_analysis import AIUsageLog
from app.models.supervision import DailyTask, HealthReport, ProactiveCoachEvent
from app.models.training import ExercisePR, WorkoutSession
from app.models.weight_log import WeightLog
from app.providers.ai.base import HealthAnswerProvider
from app.schemas.supervision import HealthReportRead
from app.services.daily_nutrition_service import DailyNutritionService


class HealthReportService:
    RULE_VERSION = "health_report_v1"
    PROMPT_VERSION = "health_report_summary_v1"

    def __init__(
        self,
        session: AsyncSession,
        provider: HealthAnswerProvider,
        settings: Settings,
    ) -> None:
        self.session = session
        self.provider = provider
        self.settings = settings
        self.nutrition = DailyNutritionService(session)

    async def generate(
        self,
        user_id: UUID,
        report_type: str,
        reference: date | None = None,
        *,
        force: bool = False,
    ) -> HealthReport:
        if report_type not in {"daily", "weekly", "monthly"}:
            raise AppError("invalid_report_type", "Unsupported report type.", 422)
        timezone = await self.nutrition.timezone(user_id)
        current = reference or datetime.now(timezone).date()
        period_start, period_end = self._period(report_type, current)
        existing = await self.session.scalar(
            select(HealthReport).where(
                HealthReport.user_id == user_id,
                HealthReport.report_type == report_type,
                HealthReport.period_start == period_start,
                HealthReport.period_end == period_end,
            )
        )
        if existing and not force:
            return existing
        if existing and existing.regeneration_count >= self.settings.report_regeneration_limit:
            raise AppError(
                "report_regeneration_limit",
                "This report has reached its regeneration limit.",
                429,
            )
        metrics = await self._metrics(user_id, period_start, period_end)
        snapshot_hash = hashlib.sha256(
            json.dumps(metrics, sort_keys=True, default=str).encode()
        ).hexdigest()
        if existing and existing.input_snapshot_hash == snapshot_hash:
            return existing
        started = perf_counter()
        generated = await self.provider.answer(
            f"请总结这份{report_type}结构化健康报告。",
            f"{report_type}_report",
            metrics,
            [],
        )
        latency_ms = max(0, round((perf_counter() - started) * 1000))
        actions = self._actions(metrics)
        if existing is None:
            report = HealthReport(
                user_id=user_id,
                report_type=report_type,
                period_start=period_start,
                period_end=period_end,
                metrics_snapshot=metrics,
                summary=generated.answer,
                next_actions=actions,
                rule_version=self.RULE_VERSION,
                prompt_version=self.PROMPT_VERSION,
                input_snapshot_hash=snapshot_hash,
                provider=generated.provider,
                model=generated.model,
                regeneration_count=0,
            )
            self.session.add(report)
        else:
            report = existing
            report.metrics_snapshot = metrics
            report.summary = generated.answer
            report.next_actions = actions
            report.input_snapshot_hash = snapshot_hash
            report.provider = generated.provider
            report.model = generated.model
            report.regeneration_count += 1
        self.session.add(
            AIUsageLog(
                user_id=user_id,
                provider=generated.provider,
                model=generated.model,
                task=f"{report_type}_report",
                input_tokens=generated.input_tokens,
                output_tokens=generated.output_tokens,
                image_count=0,
                latency_ms=latency_ms,
                status="success",
            )
        )
        await self.session.commit()
        await self.session.refresh(report)
        return report

    async def list_reports(
        self,
        user_id: UUID,
        report_type: str | None = None,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> list[HealthReport]:
        statement = select(HealthReport).where(HealthReport.user_id == user_id)
        if report_type:
            statement = statement.where(HealthReport.report_type == report_type)
        return list(
            (
                await self.session.scalars(
                    statement.order_by(
                        HealthReport.period_end.desc(), HealthReport.created_at.desc()
                    )
                    .limit(limit)
                    .offset(offset)
                )
            ).all()
        )

    async def _metrics(self, user_id: UUID, start: date, end: date) -> dict[str, object]:
        timezone = await self.nutrition.timezone(user_id)
        start_at, end_at = self.nutrition._utc_bounds(start, end, timezone)
        days = (end - start).days + 1
        nutrition = await self.nutrition.range(user_id, start, end)
        recorded_days = [item for item in nutrition if item.meal_count > 0]

        weights = list(
            (
                await self.session.scalars(
                    select(WeightLog)
                    .where(
                        WeightLog.user_id == user_id,
                        WeightLog.measured_on >= start,
                        WeightLog.measured_on <= end,
                        WeightLog.deleted_at.is_(None),
                    )
                    .order_by(WeightLog.measured_on)
                )
            ).all()
        )
        previous_start = start - timedelta(days=days)
        previous_weight_average = await self.session.scalar(
            select(func.avg(WeightLog.weight_kg)).where(
                WeightLog.user_id == user_id,
                WeightLog.measured_on >= previous_start,
                WeightLog.measured_on < start,
                WeightLog.deleted_at.is_(None),
            )
        )
        trailing_7d_weight_average = await self.session.scalar(
            select(func.avg(WeightLog.weight_kg)).where(
                WeightLog.user_id == user_id,
                WeightLog.measured_on >= end - timedelta(days=6),
                WeightLog.measured_on <= end,
                WeightLog.deleted_at.is_(None),
            )
        )
        steps = list(
            (
                await self.session.scalars(
                    select(StepLog).where(
                        StepLog.user_id == user_id,
                        StepLog.step_date >= start,
                        StepLog.step_date <= end,
                        StepLog.steps.is_not(None),
                    )
                )
            ).all()
        )
        sleeps = list(
            (
                await self.session.scalars(
                    select(SleepLog).where(
                        SleepLog.user_id == user_id,
                        SleepLog.sleep_end >= start_at - timedelta(hours=12),
                        SleepLog.sleep_end < end_at,
                    )
                )
            ).all()
        )
        workouts = list(
            (
                await self.session.scalars(
                    select(WorkoutSession).where(
                        WorkoutSession.user_id == user_id,
                        WorkoutSession.status == "completed",
                        WorkoutSession.started_at >= start_at,
                        WorkoutSession.started_at < end_at,
                    )
                )
            ).all()
        )
        prs = list(
            (
                await self.session.scalars(
                    select(ExercisePR)
                    .where(
                        ExercisePR.user_id == user_id,
                        ExercisePR.achieved_at >= start_at,
                        ExercisePR.achieved_at < end_at,
                    )
                    .order_by(ExercisePR.achieved_at.desc())
                )
            ).all()
        )
        tasks = list(
            (
                await self.session.scalars(
                    select(DailyTask).where(
                        DailyTask.user_id == user_id,
                        DailyTask.task_date >= start,
                        DailyTask.task_date <= end,
                        DailyTask.status.not_in(("cancelled",)),
                    )
                )
            ).all()
        )
        recovery = list(
            (
                await self.session.scalars(
                    select(RecoverySnapshot)
                    .where(
                        RecoverySnapshot.user_id == user_id,
                        RecoverySnapshot.snapshot_date >= start,
                        RecoverySnapshot.snapshot_date <= end,
                    )
                    .order_by(RecoverySnapshot.snapshot_date)
                )
            ).all()
        )
        lab_changes = await self.session.scalar(
            select(func.count(LabReport.id)).where(
                LabReport.user_id == user_id,
                LabReport.report_date >= start,
                LabReport.report_date <= end,
                LabReport.review_status == "confirmed",
                LabReport.deleted_at.is_(None),
            )
        )
        weight_values = [float(item.weight_kg) for item in weights]
        average_weight = self._average(weight_values)
        previous_average_weight = (
            float(previous_weight_average) if previous_weight_average is not None else None
        )
        step_values = [item.steps for item in steps if item.steps is not None]
        completed_tasks = sum(item.status == "completed" for item in tasks)
        workout_tasks = [item for item in tasks if item.task_type == "workout"]
        recovery_counts = {
            status: sum(item.status == status for item in recovery)
            for status in ("normal", "reduced", "rest")
        }
        return {
            "period_start": start.isoformat(),
            "period_end": end.isoformat(),
            "weight_start_kg": weight_values[0] if weight_values else None,
            "weight_end_kg": weight_values[-1] if weight_values else None,
            "average_weight_kg": average_weight,
            "previous_average_weight_kg": previous_average_weight,
            "average_weight_change_vs_previous_kg": (
                round(average_weight - previous_average_weight, 2)
                if average_weight is not None and previous_average_weight is not None
                else None
            ),
            "weight_change_kg": (
                round(weight_values[-1] - weight_values[0], 2) if len(weight_values) >= 2 else None
            ),
            "average_7d_weight_kg": (
                round(float(trailing_7d_weight_average), 2)
                if trailing_7d_weight_average is not None
                else None
            ),
            "average_calories": self._average(
                [float(item.totals.calories) for item in recorded_days]
            ),
            "average_protein_g": self._average(
                [float(item.totals.protein) for item in recorded_days]
            ),
            "average_carbs_g": self._average([float(item.totals.carbs) for item in recorded_days]),
            "average_fat_g": self._average([float(item.totals.fat) for item in recorded_days]),
            "average_fiber_g": self._average([float(item.totals.fiber) for item in recorded_days]),
            "nutrition_logging_completeness": round(len(recorded_days) / days, 3),
            "average_steps": self._average([float(value) for value in step_values]),
            "average_sleep_hours": self._average(
                [round(item.duration_min / 60, 2) for item in sleeps]
            ),
            "workouts_completed": len(workouts),
            "workout_completion_rate": (
                round(
                    sum(item.status == "completed" for item in workout_tasks) / len(workout_tasks),
                    3,
                )
                if workout_tasks
                else None
            ),
            "training_pr_count": len(prs),
            "training_prs": [
                {
                    "exercise_id": str(item.exercise_id),
                    "type": item.pr_type,
                    "value": float(item.value),
                    "achieved_at": item.achieved_at.isoformat(),
                }
                for item in prs[:10]
            ],
            "task_completion_rate": (round(completed_tasks / len(tasks), 3) if tasks else None),
            "tasks_completed": completed_tasks,
            "tasks_total": len(tasks),
            "confirmed_lab_reports": int(lab_changes or 0),
            "water_ml": None,
            "recovery_trend": (
                {
                    "latest": recovery[-1].status,
                    "days_recorded": len(recovery),
                    "distribution": recovery_counts,
                }
                if recovery
                else None
            ),
            "waist_change_cm": None,
            "body_fat_change_percent": None,
            "body_photo_count": 0,
            "note": "缺失数据保持为空，不按 0 处理；所有变化仅描述同期趋势。",
        }

    @staticmethod
    def _period(report_type: str, current: date) -> tuple[date, date]:
        if report_type == "daily":
            return current, current
        if report_type == "weekly":
            start = current - timedelta(days=current.weekday())
            return start, start + timedelta(days=6)
        start = current.replace(day=1)
        next_month = (start.replace(day=28) + timedelta(days=4)).replace(day=1)
        return start, next_month - timedelta(days=1)

    @staticmethod
    def _average(values: list[float]) -> float | None:
        return round(sum(values) / len(values), 2) if values else None

    @staticmethod
    def _actions(metrics: dict[str, object]) -> list[str]:
        actions: list[str] = []
        sleep = metrics.get("average_sleep_hours")
        if isinstance(sleep, int | float) and sleep < 7:
            actions.append("下一周期优先为睡眠留出更稳定的时间。")
        completeness = metrics.get("nutrition_logging_completeness")
        if isinstance(completeness, int | float) and completeness < 0.6:
            actions.append("只需补齐最容易遗漏的一餐记录，不要求每项都完美。")
        if not actions:
            actions.append("维持当前可执行节奏，继续观察连续趋势。")
        return actions[:3]

    @staticmethod
    def read(report: HealthReport) -> HealthReportRead:
        return HealthReportRead(
            id=report.id,
            report_type=report.report_type,
            period_start=report.period_start,
            period_end=report.period_end,
            metrics=report.metrics_snapshot,
            summary=report.summary,
            next_actions=report.next_actions,
            rule_version=report.rule_version,
            prompt_version=report.prompt_version,
            provider=report.provider,
            model=report.model,
            created_at=report.created_at,
        )


class ProactiveCoachService:
    """Rule-gated proactive messages with a hard per-user daily limit."""

    def __init__(self, session: AsyncSession, settings: Settings) -> None:
        self.session = session
        self.settings = settings

    async def evaluate(self, user_id: UUID, reference: date) -> list[ProactiveCoachEvent]:
        current_count = await self.session.scalar(
            select(func.count(ProactiveCoachEvent.id)).where(
                ProactiveCoachEvent.user_id == user_id,
                ProactiveCoachEvent.event_date == reference,
            )
        )
        remaining = max(0, self.settings.proactive_ai_daily_limit - int(current_count or 0))
        if remaining == 0:
            return []
        start = datetime.combine(reference - timedelta(days=2), time.min, UTC)
        end = datetime.combine(reference + timedelta(days=1), time.min, UTC)
        sleeps = list(
            (
                await self.session.scalars(
                    select(SleepLog).where(
                        SleepLog.user_id == user_id,
                        SleepLog.sleep_end >= start,
                        SleepLog.sleep_end < end,
                    )
                )
            ).all()
        )
        candidates: list[tuple[str, str, dict[str, object]]] = []
        if len(sleeps) >= 3 and all(item.duration_min < 7 * 60 for item in sleeps[-3:]):
            candidates.append(
                (
                    "three_day_low_sleep",
                    "这几天平均睡眠偏少，恢复可能受影响；今晚优先早点休息。",
                    {"days": 3, "durations_min": [item.duration_min for item in sleeps[-3:]]},
                )
            )
        values: list[ProactiveCoachEvent] = []
        for trigger, message, evidence in candidates[:remaining]:
            exists = await self.session.scalar(
                select(ProactiveCoachEvent.id).where(
                    ProactiveCoachEvent.user_id == user_id,
                    ProactiveCoachEvent.event_date == reference,
                    ProactiveCoachEvent.trigger_type == trigger,
                )
            )
            if exists:
                continue
            value = ProactiveCoachEvent(
                user_id=user_id,
                event_date=reference,
                trigger_type=trigger,
                message=message,
                evidence_snapshot=evidence,
                provider="rule_gate",
                model="proactive_v1",
            )
            self.session.add(value)
            self.session.add(
                DailyTask(
                    user_id=user_id,
                    task_date=reference,
                    task_type="custom",
                    title="健康趋势提醒",
                    description=message,
                    status="pending",
                    priority=85,
                    scheduled_time=time(8, 0),
                    source="proactive_coach",
                    source_entity_id=trigger,
                    reminder_policy={"cooldown_hours": 24, "channel": "server"},
                    dedup_key=f"custom:proactive:{trigger}",
                )
            )
            values.append(value)
        await self.session.commit()
        return values
