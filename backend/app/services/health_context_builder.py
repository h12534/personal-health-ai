from datetime import date
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.health_knowledge import LabReport, LabResult
from app.repositories.profile_repository import ProfileRepository
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.diet_adherence_service import DietAdherenceService
from app.services.recovery_service import RecoveryService
from app.services.training_context_builder import TrainingContextBuilder
from app.services.weight_trend_service import WeightTrendService


class HealthContextBuilder:
    VERSION = "health_context_v1"

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def build(self, user_id: UUID, intent: str, message: str) -> dict[str, Any]:
        context: dict[str, Any] = {
            "context_version": self.VERSION,
            "as_of": date.today().isoformat(),
        }
        profile = await ProfileRepository(self.session).by_user(user_id)
        if profile is not None:
            context["profile"] = {
                "height_cm": str(profile.height_cm) if profile.height_cm is not None else None,
                "waist_cm": str(profile.waist_cm) if profile.waist_cm is not None else None,
                "training_experience": profile.training_experience,
                "primary_goal": profile.primary_goal,
                "known_health_risks": profile.known_health_risks,
            }
        if intent in {"lab_explanation", "metabolic_health", "medical_diagnosis_request"}:
            statement = (
                select(LabResult, LabReport)
                .join(LabReport, LabReport.id == LabResult.report_id)
                .where(
                    LabReport.user_id == user_id,
                    LabReport.review_status == "confirmed",
                    LabReport.deleted_at.is_(None),
                    LabResult.user_confirmed.is_(True),
                    LabResult.deleted_at.is_(None),
                )
                .order_by(LabReport.report_date.desc(), LabResult.created_at.desc())
                .limit(30)
            )
            rows = (await self.session.execute(statement)).all()
            mentioned = [
                (result, report)
                for result, report in rows
                if result.test_name.lower() in message.lower()
                or result.normalized_name.lower() in message.lower()
            ]
            selected = mentioned or rows[:10]
            context["lab_results"] = [
                {
                    "report_id": str(report.id),
                    "report_date": report.report_date.isoformat(),
                    "test_name": result.test_name,
                    "normalized_name": result.normalized_name,
                    "value": str(result.value_numeric)
                    if result.value_numeric is not None
                    else result.value_text,
                    "unit": result.unit,
                    "reference_min": str(result.reference_min)
                    if result.reference_min is not None
                    else None,
                    "reference_max": str(result.reference_max)
                    if result.reference_max is not None
                    else None,
                    "reference_text": result.reference_text,
                    "flag": result.flag,
                }
                for result, report in selected
            ]
        if intent == "weight_health":
            adherence = await DietAdherenceService(self.session).calculate(user_id)
            context["weight_trend"] = (
                await WeightTrendService(self.session).build(
                    user_id, adherence_rate=adherence.overall_rate
                )
            ).model_dump(mode="json")
            context["nutrition_today"] = (
                await DailyNutritionService(self.session).daily(user_id)
            ).model_dump(mode="json")
            context["training"] = await TrainingContextBuilder(self.session).build(
                user_id, "training_progress", message
            )
            context["recovery"] = (await RecoveryService(self.session).today(user_id)).model_dump(
                mode="json"
            )
        elif intent in {"sleep_health", "exercise_health"}:
            context["recovery"] = (await RecoveryService(self.session).today(user_id)).model_dump(
                mode="json"
            )
            context["training"] = await TrainingContextBuilder(self.session).build(
                user_id, "today_workout", message
            )
        elif intent == "nutrition_health":
            context["nutrition_today"] = (
                await DailyNutritionService(self.session).daily(user_id)
            ).model_dump(mode="json")
        return context
