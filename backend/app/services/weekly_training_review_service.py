from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.health_activity import SleepLog
from app.models.training import (
    Exercise,
    ExercisePR,
    PainLog,
    TrainingPlan,
    WorkoutSession,
    WorkoutSet,
)
from app.schemas.training import WeeklyTrainingReviewRead
from app.services.health_activity_service import HealthActivityService
from app.services.recovery_service import RecoveryService
from app.services.training_metrics import volume_load


class WeeklyTrainingReviewService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def build(self, user_id: UUID, as_of: date | None = None) -> WeeklyTrainingReviewRead:
        end_date = as_of or date.today()
        start_date = end_date - timedelta(days=6)
        start = datetime.combine(start_date, datetime.min.time(), UTC)
        end = datetime.combine(end_date + timedelta(days=1), datetime.min.time(), UTC)
        sessions = list(
            (
                await self.session.scalars(
                    select(WorkoutSession).where(
                        WorkoutSession.user_id == user_id,
                        WorkoutSession.status == "completed",
                        WorkoutSession.started_at >= start,
                        WorkoutSession.started_at < end,
                    )
                )
            ).all()
        )
        session_ids = [item.id for item in sessions]
        sets: list[WorkoutSet] = []
        if session_ids:
            sets = list(
                (
                    await self.session.scalars(
                        select(WorkoutSet).where(
                            WorkoutSet.session_id.in_(session_ids),
                            WorkoutSet.completed.is_(True),
                            WorkoutSet.set_type != "warmup",
                        )
                    )
                ).all()
            )
        plan_sessions = await self.session.scalar(
            select(TrainingPlan.sessions_per_week).where(
                TrainingPlan.user_id == user_id,
                TrainingPlan.active.is_(True),
                TrainingPlan.deleted_at.is_(None),
            )
        )
        prs = (
            await self.session.execute(
                select(ExercisePR.pr_type, Exercise.name)
                .join(Exercise, ExercisePR.exercise_id == Exercise.id)
                .where(
                    ExercisePR.user_id == user_id,
                    ExercisePR.achieved_at >= start,
                    ExercisePR.achieved_at < end,
                )
            )
        ).all()
        step_values: list[int] = []
        health = HealthActivityService(self.session)
        for offset in range(7):
            activity = await health.daily(user_id, start_date + timedelta(days=offset))
            if activity.steps is not None:
                step_values.append(activity.steps)
        average_sleep = await self.session.scalar(
            select(func.avg(SleepLog.duration_min)).where(
                SleepLog.user_id == user_id,
                SleepLog.sleep_end >= start,
                SleepLog.sleep_end < end,
            )
        )
        pain_count = int(
            await self.session.scalar(
                select(func.count(PainLog.id)).where(
                    PainLog.user_id == user_id,
                    PainLog.created_at >= start,
                    PainLog.created_at < end,
                )
            )
            or 0
        )
        recovery = await RecoveryService(self.session).today(user_id)
        total_volume = sum(
            (volume_load(item.weight_kg, item.reps, item.set_type) for item in sets),
            Decimal("0"),
        )
        observations = [
            f"本周完成 {len(sessions)}/{int(plan_sessions or 0)} 次计划训练。",
            f"累计 {len(sets)} 个有效工作组；训练容量仅作为多项趋势之一。",
        ]
        if step_values:
            observations.append(f"有数据日平均步数 {sum(step_values) // len(step_values)}。")
        if average_sleep is not None:
            observations.append(f"平均睡眠约 {int(average_sleep) // 60} 小时。")
        next_actions = ["保持可恢复的力量训练与日常步行，不用惩罚性运动补偿饮食。"]
        if recovery.status == "reduced":
            next_actions.append("恢复信号偏低，下次训练可保守降低负荷或减少一组。")
        if average_sleep is not None and int(average_sleep) < 390:
            next_actions.append("优先增加睡眠机会，不追加高强度有氧。")
        return WeeklyTrainingReviewRead(
            date_from=start_date,
            date_to=end_date,
            planned_sessions=int(plan_sessions or 0),
            completed_sessions=len(sessions),
            effective_sets=len(sets),
            volume_load=total_volume,
            personal_records=[f"{name} · {pr_type}" for pr_type, name in prs],
            average_steps=(sum(step_values) // len(step_values) if step_values else None),
            average_sleep_minutes=(int(average_sleep) if average_sleep is not None else None),
            recovery_status=recovery.status,
            pain_logs=pain_count,
            observations=observations,
            next_actions=next_actions,
        )
