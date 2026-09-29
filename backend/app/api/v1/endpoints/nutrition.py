from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.nutrition import (
    DailyNutrition,
    NutritionGoalRead,
    NutritionGoalUpdate,
    NutritionGoalWrite,
    NutritionRangeDay,
)
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.nutrition_goal_service import NutritionGoalService

router = APIRouter()


@router.get("/daily", response_model=DataResponse[DailyNutrition])
async def daily_nutrition(
    on_date: date | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DailyNutrition]:
    return DataResponse(data=await DailyNutritionService(session).daily(user.id, on_date))


@router.get("/range", response_model=DataResponse[list[NutritionRangeDay]])
async def nutrition_range(
    date_from: date = Query(alias="from"),
    date_to: date = Query(alias="to"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[NutritionRangeDay]]:
    days = await DailyNutritionService(session).range(user.id, date_from, date_to)
    return DataResponse(data=days, meta={"count": len(days)})


@router.get("/goals/current", response_model=DataResponse[NutritionGoalRead])
async def current_goal(
    on_date: date | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[NutritionGoalRead]:
    goal = await NutritionGoalService(session).current(user.id, on_date)
    return DataResponse(data=NutritionGoalRead.model_validate(goal))


@router.get("/goals/suggested", response_model=DataResponse[NutritionGoalWrite])
async def suggested_goal(
    on_date: date | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[NutritionGoalWrite]:
    return DataResponse(data=await NutritionGoalService(session).suggested(user.id, on_date))


@router.post(
    "/goals", response_model=DataResponse[NutritionGoalRead], status_code=status.HTTP_201_CREATED
)
async def create_goal(
    payload: NutritionGoalWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[NutritionGoalRead]:
    goal = await NutritionGoalService(session).create(user.id, payload)
    return DataResponse(data=NutritionGoalRead.model_validate(goal))


@router.patch("/goals/{goal_id}", response_model=DataResponse[NutritionGoalRead])
async def update_goal(
    goal_id: UUID,
    payload: NutritionGoalUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[NutritionGoalRead]:
    goal = await NutritionGoalService(session).update(user.id, goal_id, payload)
    return DataResponse(data=NutritionGoalRead.model_validate(goal))
