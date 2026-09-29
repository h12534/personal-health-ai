from datetime import datetime
from typing import Any, cast
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.meal_analysis import MealAnalysisItem, MealAnalysisSession


class MealAnalysisRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    @staticmethod
    def _loads() -> tuple[Any, ...]:
        return (
            selectinload(MealAnalysisSession.image),
            selectinload(MealAnalysisSession.items).selectinload(MealAnalysisItem.matched_food),
        )

    async def by_id(self, user_id: UUID, analysis_id: UUID) -> MealAnalysisSession | None:
        value = await self.session.scalar(
            select(MealAnalysisSession)
            .options(*self._loads())
            .where(
                MealAnalysisSession.id == analysis_id,
                MealAnalysisSession.user_id == user_id,
                MealAnalysisSession.deleted_at.is_(None),
            )
        )
        return cast(MealAnalysisSession | None, value)

    async def by_id_for_update(
        self, user_id: UUID, analysis_id: UUID
    ) -> MealAnalysisSession | None:
        value = await self.session.scalar(
            select(MealAnalysisSession)
            .options(*self._loads())
            .where(
                MealAnalysisSession.id == analysis_id,
                MealAnalysisSession.user_id == user_id,
                MealAnalysisSession.deleted_at.is_(None),
            )
            .with_for_update()
        )
        return cast(MealAnalysisSession | None, value)

    async def for_worker(
        self, analysis_id: UUID, *, lock: bool = False
    ) -> MealAnalysisSession | None:
        statement = (
            select(MealAnalysisSession)
            .options(*self._loads())
            .where(
                MealAnalysisSession.id == analysis_id,
                MealAnalysisSession.deleted_at.is_(None),
            )
        )
        if lock:
            statement = statement.with_for_update(skip_locked=True)
        value = await self.session.scalar(statement)
        return cast(MealAnalysisSession | None, value)

    async def by_idempotency(self, user_id: UUID, key: str) -> MealAnalysisSession | None:
        value = await self.session.scalar(
            select(MealAnalysisSession)
            .options(*self._loads())
            .where(
                MealAnalysisSession.user_id == user_id,
                MealAnalysisSession.idempotency_key == key,
                MealAnalysisSession.deleted_at.is_(None),
            )
        )
        return cast(MealAnalysisSession | None, value)

    async def item(self, analysis_id: UUID, item_id: UUID) -> MealAnalysisItem | None:
        value = await self.session.scalar(
            select(MealAnalysisItem)
            .options(selectinload(MealAnalysisItem.matched_food))
            .where(
                MealAnalysisItem.id == item_id,
                MealAnalysisItem.session_id == analysis_id,
                MealAnalysisItem.deleted_at.is_(None),
            )
        )
        return cast(MealAnalysisItem | None, value)

    async def count_created_since(self, user_id: UUID, since: datetime) -> int:
        value = await self.session.scalar(
            select(func.count(MealAnalysisSession.id)).where(
                MealAnalysisSession.user_id == user_id,
                MealAnalysisSession.created_at >= since,
            )
        )
        return int(value or 0)
