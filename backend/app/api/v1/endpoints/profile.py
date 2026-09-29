from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.profile import HealthProfileRead, HealthProfileWrite
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
