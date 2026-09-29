from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.nutrition_repository import NutritionGoalRepository
from app.schemas.diet_coach import DietAdherenceRead
from app.services.daily_nutrition_service import DailyNutritionService


def _rate(numerator: int, denominator: int) -> Decimal:
    if denominator <= 0:
        return Decimal("0")
    return (Decimal(numerator) / Decimal(denominator)).quantize(
        Decimal("0.001"), rounding=ROUND_HALF_UP
    )


class DietAdherenceService:
    def __init__(self, session: AsyncSession) -> None:
        self.daily = DailyNutritionService(session)
        self.goals = NutritionGoalRepository(session)

    async def calculate(
        self, user_id: UUID, as_of: date | None = None, days: int = 14
    ) -> DietAdherenceRead:
        reference = as_of or date.today()
        days = max(7, min(days, 28))
        start = reference - timedelta(days=days - 1)
        records = await self.daily.range(user_id, start, reference)
        logged = complete = calorie_ok = protein_ok = 0
        for record in records:
            goal = await self.goals.current(user_id, record.date)
            if record.meal_count > 0:
                logged += 1
            if record.meal_count >= 2:
                complete += 1
            if goal and record.meal_count >= 2:
                calories = Decimal(record.totals.calories)
                if (
                    Decimal("0.90") * goal.calorie_target
                    <= calories
                    <= Decimal("1.10") * goal.calorie_target
                ):
                    calorie_ok += 1
                if Decimal(record.totals.protein) >= Decimal("0.90") * goal.protein_target_g:
                    protein_ok += 1
        calorie_rate = _rate(calorie_ok, complete)
        protein_rate = _rate(protein_ok, complete)
        logging_rate = _rate(complete, days)
        overall = (
            logging_rate * Decimal("0.4")
            + calorie_rate * Decimal("0.3")
            + protein_rate * Decimal("0.3")
        ).quantize(Decimal("0.001"))
        return DietAdherenceRead(
            date_from=start,
            date_to=reference,
            total_days=days,
            logged_days=logged,
            complete_days=complete,
            calorie_adherent_days=calorie_ok,
            protein_adherent_days=protein_ok,
            logging_rate=logging_rate,
            calorie_adherence_rate=calorie_rate,
            protein_adherence_rate=protein_rate,
            overall_rate=overall,
        )
