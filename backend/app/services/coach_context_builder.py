from datetime import UTC, date, datetime
from typing import Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.diet_coach_repository import DietCoachRepository
from app.repositories.profile_repository import ProfileRepository
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.diet_adherence_service import DietAdherenceService
from app.services.health_activity_service import HealthActivityService
from app.services.meal_service import MealService
from app.services.next_meal_planner import NextMealPlanner
from app.services.recovery_service import RecoveryService
from app.services.weight_trend_service import WeightTrendService


class CoachContextBuilder:
    VERSION = "coach_context_v1"

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.profile_repo = ProfileRepository(session)
        self.coach_repo = DietCoachRepository(session)

    async def build(self, user_id: UUID, intent: str) -> dict[str, Any]:
        context: dict[str, Any] = {
            "context_version": self.VERSION,
            "as_of": date.today().isoformat(),
            "current_time": datetime.now(UTC).isoformat(),
        }
        profile = await self.profile_repo.by_user(user_id)
        if profile:
            context["profile"] = {
                "phase": profile.current_goal_phase,
                "activity_level": profile.activity_level,
                "dietary_environment": profile.dietary_environment,
                "allergies": profile.allergies,
                "disliked_foods": profile.disliked_foods,
                "timezone": profile.timezone,
            }
        memories = await self.coach_repo.memories(user_id)
        context["dietary_memories"] = [
            {"kind": item.kind, "value": item.value} for item in memories[:30]
        ]
        meal_intents = {
            "meal_decision",
            "meal_recommendation",
            "daily_summary",
            "nutrition_question",
            "hunger",
            "restaurant_choice",
            "canteen_choice",
            "food_comparison",
        }
        if intent in meal_intents:
            daily = await DailyNutritionService(self.session).daily(user_id)
            context["daily_nutrition"] = daily.model_dump(mode="json")
            try:
                next_meal = await NextMealPlanner(self.session).plan(user_id)
                context["next_meal"] = next_meal.model_dump(mode="json")
            except Exception:
                context["next_meal"] = None
            meals = await MealService(self.session).list(user_id, date.today(), date.today())
            context["recent_meal"] = meals[-1].model_dump(mode="json") if meals else None
            context["activity"] = (
                await HealthActivityService(self.session).daily(user_id)
            ).model_dump(mode="json")
            context["recovery"] = (await RecoveryService(self.session).today(user_id)).model_dump(
                mode="json"
            )
            canteens = await self.coach_repo.canteens(user_id)
            context["canteens"] = [
                {
                    "id": str(canteen.id),
                    "name": canteen.name,
                    "available_dishes": sum(
                        len([dish for dish in stall.dishes if dish.is_available])
                        for stall in canteen.stalls
                    ),
                }
                for canteen in canteens[:10]
            ]
        if intent in {"weight_progress", "diet_plan", "daily_summary"}:
            adherence = await DietAdherenceService(self.session).calculate(user_id)
            trend = await WeightTrendService(self.session).build(
                user_id, adherence_rate=adherence.overall_rate
            )
            context["adherence"] = adherence.model_dump(mode="json")
            context["weight_trend"] = trend.model_dump(mode="json")
        return context
