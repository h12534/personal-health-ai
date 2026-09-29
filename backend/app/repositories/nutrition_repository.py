from datetime import date
from typing import cast
from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.nutrition_goal import NutritionGoal


class NutritionGoalRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def current(self, user_id: UUID, on_date: date) -> NutritionGoal | None:
        result = await self.session.scalar(
            select(NutritionGoal)
            .where(
                NutritionGoal.user_id == user_id,
                NutritionGoal.effective_from <= on_date,
                or_(NutritionGoal.effective_to.is_(None), NutritionGoal.effective_to >= on_date),
                NutritionGoal.deleted_at.is_(None),
            )
            .order_by(NutritionGoal.effective_from.desc(), NutritionGoal.created_at.desc())
            .limit(1)
        )
        return cast(NutritionGoal | None, result)

    async def by_id(self, user_id: UUID, goal_id: UUID) -> NutritionGoal | None:
        result = await self.session.scalar(
            select(NutritionGoal).where(
                NutritionGoal.id == goal_id,
                NutritionGoal.user_id == user_id,
                NutritionGoal.deleted_at.is_(None),
            )
        )
        return cast(NutritionGoal | None, result)
