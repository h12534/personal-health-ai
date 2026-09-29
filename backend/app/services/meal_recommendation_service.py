from datetime import UTC, date, datetime, time, timedelta
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.diet_coach_repository import DietCoachRepository
from app.repositories.food_repository import FoodRepository
from app.repositories.meal_repository import MealRepository
from app.schemas.diet_coach import MealRecommendationRead, MealTargetRange


class MealRecommendationService:
    """Ranks real user choices; language models never invent candidates."""

    def __init__(self, session: AsyncSession) -> None:
        self.coach = DietCoachRepository(session)
        self.foods = FoodRepository(session)
        self.meals = MealRepository(session)

    async def recommend(
        self, user_id: UUID, target: MealTargetRange
    ) -> list[MealRecommendationRead]:
        center = Decimal(target.calories_min + target.calories_max) / Decimal("2")
        protein = (target.protein_min_g + target.protein_max_g) / Decimal("2")
        repeated = await self._recent_counts(user_id)
        candidates: list[tuple[str, UUID, str, Decimal, Decimal]] = []
        for saved in await self.coach.saved_meals(user_id):
            calories = sum((item.calories for item in saved.items), Decimal("0"))
            protein_g = sum((item.protein for item in saved.items), Decimal("0"))
            candidates.append(("saved_meal", saved.id, saved.name, calories, protein_g))
        for canteen in await self.coach.canteens(user_id):
            for stall in canteen.stalls:
                for dish in stall.dishes:
                    if dish.is_available:
                        candidates.append(
                            ("canteen_dish", dish.id, dish.name, dish.calories, dish.protein_g)
                        )
        for food in await self.foods.recent(user_id, limit=15):
            weight = food.serving_weight_g or Decimal("100")
            candidates.append(
                (
                    "recent_food",
                    food.id,
                    food.name,
                    food.calories_per_100g * weight / Decimal("100"),
                    food.protein_per_100g * weight / Decimal("100"),
                )
            )
        ranked: list[MealRecommendationRead] = []
        for source, source_id, name, calories, protein_g in candidates:
            calorie_fit = max(
                Decimal("0"), Decimal("1") - abs(calories - center) / max(center, Decimal("1"))
            )
            protein_fit = min(Decimal("1"), protein_g / max(protein, Decimal("1")))
            repeat_count = repeated.get(name, 0)
            variety_factor = max(
                Decimal("0.65"), Decimal("1") - Decimal(repeat_count) * Decimal("0.08")
            )
            score = (calorie_fit * Decimal("0.55") + protein_fit * Decimal("0.45")) * variety_factor
            reasons = ["来自你的常用选择，可直接执行"]
            if protein_g >= target.protein_min_g:
                reasons.append("蛋白质达到下一餐建议下限")
            if repeat_count >= 3:
                reasons.append("最近已多次吃过，可按意愿换一种；系统不会强制")
            ranked.append(
                MealRecommendationRead(
                    source=source,  # type: ignore[arg-type]
                    source_id=source_id,
                    name=name,
                    calories=calories.quantize(Decimal("0.1")),
                    protein_g=protein_g.quantize(Decimal("0.1")),
                    match_score=(score * 100).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP),
                    reasons=reasons,
                )
            )
        return sorted(ranked, key=lambda item: item.match_score, reverse=True)[:12]

    async def _recent_counts(self, user_id: UUID) -> dict[str, int]:
        end = datetime.combine(date.today() + timedelta(days=1), time.min, UTC)
        start = end - timedelta(days=7)
        counts: dict[str, int] = {}
        for meal in await self.meals.list_for_user(user_id, start, end):
            for item in meal.items:
                counts[item.food_name_snapshot] = counts.get(item.food_name_snapshot, 0) + 1
        return counts
