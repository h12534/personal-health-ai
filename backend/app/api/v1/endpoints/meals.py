from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.meal import MealCreate, MealItemUpdate, MealItemWrite, MealRead, MealUpdate
from app.services.meal_service import MealService

router = APIRouter()


@router.post("", response_model=DataResponse[MealRead], status_code=status.HTTP_201_CREATED)
async def create_meal(
    payload: MealCreate,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[MealRead]:
    meal = await MealService(session).create(user.id, payload, idempotency_key)
    return DataResponse(data=meal)


@router.get("", response_model=DataResponse[list[MealRead]])
async def list_meals(
    date_from: date | None = Query(default=None, alias="from"),
    date_to: date | None = Query(default=None, alias="to"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[MealRead]]:
    meals = await MealService(session).list(user.id, date_from, date_to)
    return DataResponse(data=meals, meta={"count": len(meals)})


@router.get("/{meal_id}", response_model=DataResponse[MealRead])
async def get_meal(
    meal_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[MealRead]:
    return DataResponse(data=await MealService(session).get(user.id, meal_id))


@router.patch("/{meal_id}", response_model=DataResponse[MealRead])
async def update_meal(
    meal_id: UUID,
    payload: MealUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[MealRead]:
    return DataResponse(data=await MealService(session).update(user.id, meal_id, payload))


@router.delete("/{meal_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_meal(
    meal_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await MealService(session).delete(user.id, meal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{meal_id}/items", response_model=DataResponse[MealRead])
async def add_meal_item(
    meal_id: UUID,
    payload: MealItemWrite,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[MealRead]:
    meal = await MealService(session).add_item(user.id, meal_id, payload, idempotency_key)
    return DataResponse(data=meal)


@router.patch("/{meal_id}/items/{item_id}", response_model=DataResponse[MealRead])
async def update_meal_item(
    meal_id: UUID,
    item_id: UUID,
    payload: MealItemUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[MealRead]:
    meal = await MealService(session).update_item(user.id, meal_id, item_id, payload)
    return DataResponse(data=meal)


@router.delete("/{meal_id}/items/{item_id}", response_model=DataResponse[MealRead])
async def delete_meal_item(
    meal_id: UUID,
    item_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[MealRead]:
    meal = await MealService(session).delete_item(user.id, meal_id, item_id)
    return DataResponse(data=meal)
