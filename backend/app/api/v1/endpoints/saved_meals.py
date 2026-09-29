from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.diet_coach import SavedMealLogWrite, SavedMealRead, SavedMealWrite
from app.schemas.meal import MealRead
from app.services.meal_service import MealService
from app.services.saved_meal_service import SavedMealService

router = APIRouter()


@router.get("", response_model=DataResponse[list[SavedMealRead]])
async def list_saved_meals(
    user: User = Depends(get_current_user), session: AsyncSession = Depends(get_db)
) -> DataResponse[list[SavedMealRead]]:
    values = await SavedMealService(session).list(user.id)
    return DataResponse(data=[SavedMealRead.model_validate(value) for value in values])


@router.post("", response_model=DataResponse[SavedMealRead], status_code=status.HTTP_201_CREATED)
async def create_saved_meal(
    payload: SavedMealWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[SavedMealRead]:
    value = await SavedMealService(session).create(user.id, payload)
    return DataResponse(data=SavedMealRead.model_validate(value))


@router.post("/{saved_meal_id}/log", response_model=DataResponse[MealRead])
async def log_saved_meal(
    saved_meal_id: UUID,
    payload: SavedMealLogWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[MealRead]:
    meal = await SavedMealService(session).log(user.id, saved_meal_id, payload)
    return DataResponse(data=MealService._read(meal))


@router.delete("/{saved_meal_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_saved_meal(
    saved_meal_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await SavedMealService(session).delete(user.id, saved_meal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
