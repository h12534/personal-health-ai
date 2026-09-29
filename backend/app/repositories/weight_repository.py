from datetime import date
from typing import cast
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.weight_log import WeightLog


class WeightRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def list_for_user(
        self,
        user_id: UUID,
        date_from: date | None = None,
        date_to: date | None = None,
    ) -> list[WeightLog]:
        query = select(WeightLog).where(
            WeightLog.user_id == user_id,
            WeightLog.deleted_at.is_(None),
        )
        if date_from:
            query = query.where(WeightLog.measured_on >= date_from)
        if date_to:
            query = query.where(WeightLog.measured_on <= date_to)
        query = query.order_by(WeightLog.measured_on.asc())
        return list((await self.session.scalars(query)).all())

    async def by_id(self, user_id: UUID, log_id: UUID) -> WeightLog | None:
        result = await self.session.scalar(
            select(WeightLog).where(
                WeightLog.id == log_id,
                WeightLog.user_id == user_id,
                WeightLog.deleted_at.is_(None),
            )
        )
        return cast(WeightLog | None, result)

    async def by_date(self, user_id: UUID, measured_on: date) -> WeightLog | None:
        result = await self.session.scalar(
            select(WeightLog).where(
                WeightLog.user_id == user_id,
                WeightLog.measured_on == measured_on,
                WeightLog.deleted_at.is_(None),
            )
        )
        return cast(WeightLog | None, result)

    async def by_date_including_deleted(self, user_id: UUID, measured_on: date) -> WeightLog | None:
        result = await self.session.scalar(
            select(WeightLog).where(
                WeightLog.user_id == user_id,
                WeightLog.measured_on == measured_on,
            )
        )
        return cast(WeightLog | None, result)

    async def add(self, log: WeightLog) -> WeightLog:
        self.session.add(log)
        await self.session.flush()
        return log
