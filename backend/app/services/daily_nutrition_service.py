from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.meal import MealLog
from app.repositories.meal_repository import MealRepository
from app.repositories.profile_repository import ProfileRepository
from app.schemas.nutrition import DailyNutrition, NutritionRangeDay, NutritionTotals
from app.services.nutrition_calculator import quantize_nutrition

MEAL_TYPES = ("breakfast", "lunch", "dinner", "snack")


class DailyNutritionService:
    def __init__(self, session: AsyncSession) -> None:
        self.meals = MealRepository(session)
        self.profiles = ProfileRepository(session)

    async def daily(self, user_id: UUID, on_date: date | None = None) -> DailyNutrition:
        timezone = await self._timezone(user_id)
        reference = on_date or datetime.now(timezone).date()
        start, end = self._utc_bounds(reference, reference, timezone)
        meals = await self.meals.list_for_user(user_id, start, end)
        return self._daily_from_meals(reference, meals)

    async def range(self, user_id: UUID, date_from: date, date_to: date) -> list[NutritionRangeDay]:
        if date_to < date_from or (date_to - date_from).days > 366:
            from app.core.errors import AppError

            raise AppError(
                "invalid_date_range", "Nutrition date range is invalid or too large.", 422
            )
        timezone = await self._timezone(user_id)
        start, end = self._utc_bounds(date_from, date_to, timezone)
        meals = await self.meals.list_for_user(user_id, start, end)
        grouped: dict[date, list[MealLog]] = {}
        for meal in meals:
            eaten_at = meal.eaten_at
            if eaten_at.tzinfo is None:
                eaten_at = eaten_at.replace(tzinfo=UTC)
            local_date = eaten_at.astimezone(timezone).date()
            grouped.setdefault(local_date, []).append(meal)
        result: list[NutritionRangeDay] = []
        cursor = date_from
        while cursor <= date_to:
            day = self._daily_from_meals(cursor, grouped.get(cursor, []))
            result.append(
                NutritionRangeDay(date=cursor, totals=day.totals, meal_count=day.meal_count)
            )
            cursor += timedelta(days=1)
        return result

    async def timezone(self, user_id: UUID) -> ZoneInfo:
        return await self._timezone(user_id)

    @staticmethod
    def _daily_from_meals(on_date: date, meals: list[MealLog]) -> DailyNutrition:
        breakdown = {name: NutritionTotals() for name in MEAL_TYPES}
        meal_counts = {name: 0 for name in MEAL_TYPES}
        totals = NutritionTotals()
        for meal in meals:
            current = breakdown.setdefault(meal.meal_type, NutritionTotals())
            meal_counts[meal.meal_type] = meal_counts.get(meal.meal_type, 0) + 1
            DailyNutritionService._add(current, meal)
            DailyNutritionService._add(totals, meal)
        return DailyNutrition(
            date=on_date,
            totals=totals,
            meals=breakdown,
            meal_counts=meal_counts,
            meal_count=len(meals),
        )

    @staticmethod
    def _add(target: NutritionTotals, meal: MealLog) -> None:
        target.calories = quantize_nutrition(target.calories + meal.total_calories)
        target.protein = quantize_nutrition(target.protein + meal.total_protein)
        target.carbs = quantize_nutrition(target.carbs + meal.total_carbs)
        target.fat = quantize_nutrition(target.fat + meal.total_fat)
        target.fiber = quantize_nutrition(target.fiber + meal.total_fiber)

    async def _timezone(self, user_id: UUID) -> ZoneInfo:
        profile = await self.profiles.by_user(user_id)
        name = profile.timezone if profile else "Asia/Shanghai"
        try:
            return ZoneInfo(name)
        except ZoneInfoNotFoundError:
            return ZoneInfo("UTC")

    @staticmethod
    def _utc_bounds(
        start_date: date, end_date: date, timezone: ZoneInfo
    ) -> tuple[datetime, datetime]:
        start = datetime.combine(start_date, time.min, timezone).astimezone(UTC)
        end = datetime.combine(end_date + timedelta(days=1), time.min, timezone).astimezone(UTC)
        return start, end
