from datetime import UTC, date, datetime, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.training import Exercise, WorkoutSession
from app.services.health_activity_service import HealthActivityService
from app.services.recovery_service import RecoveryService
from app.services.training_plan_service import TrainingPlanService
from app.services.workout_service import WeightSuggestionService, WorkoutService


class TrainingContextBuilder:
    VERSION = "training_context_v1"

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def build(self, user_id: UUID, intent: str, message: str) -> dict[str, Any]:
        context: dict[str, Any] = {
            "context_version": self.VERSION,
            "as_of": datetime.now(UTC).isoformat(),
        }
        plans = await TrainingPlanService(self.session).list_all(user_id)
        active = next((item for item in plans if item.active), plans[0] if plans else None)
        if active:
            context["active_plan"] = {
                "id": str(active.id),
                "name": active.name,
                "sessions_per_week": active.sessions_per_week,
                "days": [
                    {
                        "id": str(day.id),
                        "name": day.name,
                        "focus": day.focus,
                        "estimated_duration_min": day.estimated_duration_min,
                    }
                    for day in active.days
                ],
            }
        today_sessions = await WorkoutService(self.session).list_all(
            user_id, date.today(), date.today()
        )
        context["today_training_status"] = (
            "completed"
            if any(item.status == "completed" for item in today_sessions)
            else "in_progress"
            if any(item.status == "in_progress" for item in today_sessions)
            else "planned"
            if active
            else "rest_or_unplanned"
        )
        if intent in {
            "weight_selection",
            "progression",
            "exercise_help",
            "training_progress",
        }:
            exercises = list(
                (
                    await self.session.scalars(select(Exercise).where(Exercise.active.is_(True)))
                ).all()
            )
            mentioned = next((item for item in exercises if item.name in message), None)
            if mentioned:
                context["exercise"] = {
                    "id": str(mentioned.id),
                    "name": mentioned.name,
                    "movement_pattern": mentioned.movement_pattern,
                    "instructions": mentioned.instructions,
                    "execution_cues": mentioned.execution_cues,
                    "safety_notes": mentioned.safety_notes,
                }
                context["recent_sets"] = await WeightSuggestionService(self.session).recent_sets(
                    user_id, mentioned.id
                )
        if intent in {"recovery", "sleep_recovery", "today_workout", "weight_selection"}:
            recovery = await RecoveryService(self.session).today(user_id)
            context["recovery"] = recovery.model_dump(mode="json")
        if intent in {"steps", "cardio", "recovery", "today_workout"}:
            activity = await HealthActivityService(self.session).daily(user_id)
            context["activity"] = activity.model_dump(mode="json")
        if intent in {"missed_workout", "schedule_change"} and active:
            completed_week = await self.session.scalar(
                select(WorkoutSession.id)
                .where(
                    WorkoutSession.user_id == user_id,
                    WorkoutSession.status == "completed",
                    WorkoutSession.started_at >= datetime.now(UTC) - timedelta(days=7),
                )
                .limit(1)
            )
            context["reschedule"] = {
                "rule": "shift_forward_keep_48h_when_possible",
                "double_session": False,
                "has_completed_session_this_week": completed_week is not None,
            }
        return context
