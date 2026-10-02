from datetime import datetime
from typing import cast
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.meal import MealItem, MealLog


class MealRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def list_for_user(
        self,
        user_id: UUID,
        start: datetime,
        end: datetime,
        *,
        limit: int | None = None,
        offset: int = 0,
    ) -> list[MealLog]:
        statement = (
            select(MealLog)
            .options(selectinload(MealLog.items))
            .where(
                MealLog.user_id == user_id,
                MealLog.eaten_at >= start,
                MealLog.eaten_at < end,
                MealLog.deleted_at.is_(None),
            )
            .order_by(MealLog.eaten_at.asc())
        )
        if limit is not None:
            statement = statement.limit(limit).offset(offset)
        meals = await self.session.scalars(statement)
        return list(meals.all())

    async def by_id(self, user_id: UUID, meal_id: UUID) -> MealLog | None:
        result = await self.session.scalar(
            select(MealLog)
            .options(selectinload(MealLog.items))
            .where(
                MealLog.id == meal_id,
                MealLog.user_id == user_id,
                MealLog.deleted_at.is_(None),
            )
        )
        return cast(MealLog | None, result)

    async def by_idempotency(self, user_id: UUID, key: str) -> MealLog | None:
        result = await self.session.scalar(
            select(MealLog)
            .options(selectinload(MealLog.items))
            .where(
                MealLog.user_id == user_id,
                MealLog.idempotency_key == key,
                MealLog.deleted_at.is_(None),
            )
        )
        return cast(MealLog | None, result)

    async def item_by_id(self, meal_id: UUID, item_id: UUID) -> MealItem | None:
        result = await self.session.scalar(
            select(MealItem).where(
                MealItem.id == item_id,
                MealItem.meal_id == meal_id,
                MealItem.deleted_at.is_(None),
            )
        )
        return cast(MealItem | None, result)

    async def item_by_idempotency(self, meal_id: UUID, key: str) -> MealItem | None:
        result = await self.session.scalar(
            select(MealItem).where(
                MealItem.meal_id == meal_id,
                MealItem.idempotency_key == key,
                MealItem.deleted_at.is_(None),
            )
        )
        return cast(MealItem | None, result)
