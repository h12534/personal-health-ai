from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.profile import (
    HealthProfileRead,
    HealthProfileWrite,
    VisionPrivacyRead,
    VisionPrivacyWrite,
)
from app.services.profile_service import ProfileService

router = APIRouter()


@router.get("", response_model=DataResponse[HealthProfileRead])
async def get_profile(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HealthProfileRead]:
    profile = await ProfileService(session).get(user.id)
    return DataResponse(data=HealthProfileRead.model_validate(profile))


@router.put("", response_model=DataResponse[HealthProfileRead])
async def put_profile(
    payload: HealthProfileWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HealthProfileRead]:
    profile = await ProfileService(session).upsert(user.id, payload)
    return DataResponse(data=HealthProfileRead.model_validate(profile))


@router.patch("/privacy/meal-vision", response_model=DataResponse[VisionPrivacyRead])
async def patch_meal_vision_privacy(
    payload: VisionPrivacyWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[VisionPrivacyRead]:
    profile = await ProfileService(session).update_vision_privacy(user.id, payload)
    return DataResponse(
        data=VisionPrivacyRead(
            allow_third_party_vision=profile.allow_third_party_vision,
            retain_meal_images=profile.retain_meal_images,
        )
    )
