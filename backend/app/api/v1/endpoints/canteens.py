from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.diet_coach import (
    CanteenDetailRead,
    CanteenRead,
    CanteenWrite,
    DishRead,
    DishRecommendationRead,
    DishWrite,
    StallRead,
    StallWrite,
)
from app.services.canteen_service import CanteenService
from app.services.next_meal_planner import NextMealPlanner

router = APIRouter()


@router.get("", response_model=DataResponse[list[CanteenDetailRead]])
async def list_canteens(
    user: User = Depends(get_current_user), session: AsyncSession = Depends(get_db)
) -> DataResponse[list[CanteenDetailRead]]:
    values = await CanteenService(session).list_details(user.id)
    return DataResponse(data=values)


@router.post("", response_model=DataResponse[CanteenRead], status_code=status.HTTP_201_CREATED)
async def create_canteen(
    payload: CanteenWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[CanteenRead]:
    return DataResponse(
        data=CanteenRead.model_validate(await CanteenService(session).create(user.id, payload))
    )


@router.patch("/{canteen_id}", response_model=DataResponse[CanteenRead])
async def update_canteen(
    canteen_id: UUID,
    payload: CanteenWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[CanteenRead]:
    value = await CanteenService(session).update_canteen(user.id, canteen_id, payload)
    return DataResponse(data=CanteenRead.model_validate(value))


@router.post(
    "/{canteen_id}/stalls",
    response_model=DataResponse[StallRead],
    status_code=status.HTTP_201_CREATED,
)
async def create_stall(
    canteen_id: UUID,
    payload: StallWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[StallRead]:
    return DataResponse(
        data=StallRead.model_validate(
            await CanteenService(session).add_stall(user.id, canteen_id, payload)
        )
    )


@router.patch("/stalls/{stall_id}", response_model=DataResponse[StallRead])
async def update_stall(
    stall_id: UUID,
    payload: StallWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[StallRead]:
    value = await CanteenService(session).update_stall(user.id, stall_id, payload)
    return DataResponse(data=StallRead.model_validate(value))


@router.post(
    "/stalls/{stall_id}/dishes",
    response_model=DataResponse[DishRead],
    status_code=status.HTTP_201_CREATED,
)
async def create_dish(
    stall_id: UUID,
    payload: DishWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DishRead]:
    return DataResponse(
        data=DishRead.model_validate(
            await CanteenService(session).add_dish(user.id, stall_id, payload)
        )
    )


@router.patch("/dishes/{dish_id}", response_model=DataResponse[DishRead])
async def update_dish(
    dish_id: UUID,
    payload: DishWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DishRead]:
    value = await CanteenService(session).update_dish(user.id, dish_id, payload)
    return DataResponse(data=DishRead.model_validate(value))


@router.post(
    "/stalls/{stall_id}/learn-from-meal/{meal_id}", response_model=DataResponse[list[DishRead]]
)
async def learn_dishes_from_meal(
    stall_id: UUID,
    meal_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[DishRead]]:
    values = await CanteenService(session).learn_from_meal(user.id, stall_id, meal_id)
    return DataResponse(data=[DishRead.model_validate(value) for value in values])


@router.get("/recommendations", response_model=DataResponse[list[DishRecommendationRead]])
async def recommendations(
    canteen_id: UUID | None = None,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[DishRecommendationRead]]:
    plan = await NextMealPlanner(session).plan(user.id)
    values = await CanteenService(session).recommend(user.id, plan.target, canteen_id)
    return DataResponse(data=values)


@router.delete("/{canteen_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_canteen(
    canteen_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await CanteenService(session).delete_canteen(user.id, canteen_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/stalls/{stall_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_stall(
    stall_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await CanteenService(session).delete_stall(user.id, stall_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/dishes/{dish_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_dish(
    dish_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await CanteenService(session).delete_dish(user.id, dish_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
