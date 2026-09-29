from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.food import FavoriteRead, FoodCreate, FoodRead, FoodUpdate
from app.services.food_service import FoodService

router = APIRouter()


@router.get("", response_model=DataResponse[list[FoodRead]])
@router.get("/search", response_model=DataResponse[list[FoodRead]])
async def search_foods(
    q: str = Query(default="", max_length=200),
    category: str | None = Query(default=None, max_length=64),
    limit: int = Query(default=30, ge=1, le=100),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[FoodRead]]:
    foods = await FoodService(session).search(user.id, q, category, limit)
    return DataResponse(data=foods, meta={"count": len(foods)})


@router.get("/favorites", response_model=DataResponse[list[FavoriteRead]])
async def favorites(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[FavoriteRead]]:
    return DataResponse(data=await FoodService(session).favorites(user.id))


@router.get("/recent", response_model=DataResponse[list[FoodRead]])
async def recent(
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[FoodRead]]:
    return DataResponse(data=await FoodService(session).recent(user.id, limit))


@router.post("", response_model=DataResponse[FoodRead], status_code=status.HTTP_201_CREATED)
async def create_food(
    payload: FoodCreate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[FoodRead]:
    return DataResponse(data=await FoodService(session).create(user.id, payload))


@router.get("/{food_id}", response_model=DataResponse[FoodRead])
async def get_food(
    food_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[FoodRead]:
    return DataResponse(data=await FoodService(session).get(user.id, food_id))


@router.patch("/{food_id}", response_model=DataResponse[FoodRead])
async def update_food(
    food_id: UUID,
    payload: FoodUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[FoodRead]:
    return DataResponse(data=await FoodService(session).update(user.id, food_id, payload))


@router.delete("/{food_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_food(
    food_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await FoodService(session).delete(user.id, food_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{food_id}/favorite", response_model=DataResponse[FoodRead])
async def add_favorite(
    food_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[FoodRead]:
    return DataResponse(data=await FoodService(session).add_favorite(user.id, food_id))


@router.delete("/{food_id}/favorite", status_code=status.HTTP_204_NO_CONTENT)
async def remove_favorite(
    food_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await FoodService(session).remove_favorite(user.id, food_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
