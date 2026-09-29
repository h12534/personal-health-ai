from typing import cast
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.health_profile import HealthProfile


class ProfileRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def by_user(self, user_id: UUID) -> HealthProfile | None:
        result = await self.session.scalar(
            select(HealthProfile).where(HealthProfile.user_id == user_id)
        )
        return cast(HealthProfile | None, result)

    async def add(self, profile: HealthProfile) -> HealthProfile:
        self.session.add(profile)
        await self.session.flush()
        return profile
