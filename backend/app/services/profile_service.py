from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.health_profile import HealthProfile
from app.repositories.profile_repository import ProfileRepository
from app.schemas.profile import HealthProfileWrite


class ProfileService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repository = ProfileRepository(session)

    async def get(self, user_id: UUID) -> HealthProfile:
        profile = await self.repository.by_user(user_id)
        if profile is None:
            raise AppError("profile_not_found", "Health profile has not been created.", 404)
        return profile

    async def upsert(self, user_id: UUID, payload: HealthProfileWrite) -> HealthProfile:
        profile = await self.repository.by_user(user_id)
        values = payload.model_dump()
        if profile is None:
            profile = HealthProfile(user_id=user_id, **values)
            await self.repository.add(profile)
        else:
            for field, value in values.items():
                setattr(profile, field, value)
        await self.session.commit()
        await self.session.refresh(profile)
        return profile
