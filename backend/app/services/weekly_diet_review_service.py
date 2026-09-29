from datetime import date
from decimal import Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.diet_coach import DietAdjustmentRead, WeeklyReviewRead
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.diet_adherence_service import DietAdherenceService
from app.services.diet_adjustment_service import DietAdjustmentService
from app.services.weight_trend_service import WeightTrendService


class WeeklyDietReviewService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def build(self, user_id: UUID, as_of: date | None = None) -> WeeklyReviewRead:
        reference = as_of or date.today()
        adherence = await DietAdherenceService(self.session).calculate(user_id, reference, 14)
        trend = await WeightTrendService(self.session).build(
            user_id, reference, adherence.overall_rate
        )
        adjustment = await DietAdjustmentService(self.session).suggest(user_id, reference)
        days = await DailyNutritionService(self.session).range(
            user_id, adherence.date_from, adherence.date_to
        )
        recorded = [day for day in days if day.meal_count > 0]
        denominator = max(1, len(recorded))
        average_calories = sum(
            (day.totals.calories for day in recorded), start=Decimal("0")
        ) / Decimal(denominator)
        average_protein = sum(
            (day.totals.protein for day in recorded), start=Decimal("0")
        ) / Decimal(denominator)
        average_fiber = sum((day.totals.fiber for day in recorded), start=Decimal("0")) / Decimal(
            denominator
        )
        high_calorie_days = 0
        for day in recorded:
            goal = await DietAdherenceService(self.session).goals.current(user_id, day.date)
            if goal and day.totals.calories > Decimal(goal.calorie_target) * Decimal("1.15"):
                high_calorie_days += 1
        observations = [
            f"近 14 天完整记录率为 {int(adherence.logging_rate * 100)}%。",
            trend.note,
        ]
        actions = ["继续按正常节奏记录饮食和晨重", "优先保证蛋白质与规律进餐"]
        if adjustment:
            actions.insert(0, "查看热量目标微调建议；仅在你确认后才会生效")
        return WeeklyReviewRead(
            as_of=reference,
            headline="本周重点是看趋势，而不是追逐某一天的数字。",
            average_calories=average_calories,
            average_protein_g=average_protein,
            average_fiber_g=average_fiber,
            high_calorie_meal_days=high_calorie_days,
            observations=observations,
            next_actions=actions,
            trend=trend,
            adherence=adherence,
            adjustment=DietAdjustmentRead.model_validate(adjustment) if adjustment else None,
        )
