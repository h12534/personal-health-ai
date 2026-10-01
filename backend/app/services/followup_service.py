from datetime import UTC, date, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.supervision import HealthFollowup
from app.schemas.supervision import HealthFollowupCreate


class FollowupService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, user_id: UUID, payload: HealthFollowupCreate) -> HealthFollowup:
        value = HealthFollowup(
            user_id=user_id,
            lab_test_code=payload.lab_test_code,
            reason=payload.reason,
            recommended_date=payload.recommended_date,
            status="suggested",
            source=payload.source,
            source_entity_id=payload.source_entity_id,
        )
        self.session.add(value)
        await self.session.commit()
        await self.session.refresh(value)
        return value

    async def list(self, user_id: UUID, status: str | None = None) -> list[HealthFollowup]:
        statement = select(HealthFollowup).where(HealthFollowup.user_id == user_id)
        if status:
            statement = statement.where(HealthFollowup.status == status)
        return list(
            (await self.session.scalars(statement.order_by(HealthFollowup.recommended_date))).all()
        )

    async def confirm(self, user_id: UUID, followup_id: UUID) -> HealthFollowup:
        value = await self._get(user_id, followup_id)
        value.status = "confirmed"
        value.confirmed_at = datetime.now(UTC)
        await self.session.commit()
        return value

    async def update_date(
        self, user_id: UUID, followup_id: UUID, recommended_date: date
    ) -> HealthFollowup:
        value = await self._get(user_id, followup_id)
        value.recommended_date = recommended_date
        await self.session.commit()
        return value

    async def cancel(self, user_id: UUID, followup_id: UUID) -> HealthFollowup:
        value = await self._get(user_id, followup_id)
        value.status = "cancelled"
        await self.session.commit()
        return value

    async def _get(self, user_id: UUID, followup_id: UUID) -> HealthFollowup:
        value = await self.session.scalar(
            select(HealthFollowup).where(
                HealthFollowup.id == followup_id, HealthFollowup.user_id == user_id
            )
        )
        if value is None:
            raise AppError("health_followup_not_found", "Health follow-up was not found.", 404)
        return value
