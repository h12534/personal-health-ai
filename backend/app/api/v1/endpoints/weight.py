from datetime import date, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.repositories.weight_repository import WeightRepository
from app.schemas.common import DataResponse
from app.schemas.weight import (
    WeightCreate,
    WeightRead,
    WeightTrendSummary,
    WeightUpdate,
)
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.weight_service import WeightService, build_weight_trend

router = APIRouter()


@router.get("/trends", response_model=DataResponse[WeightTrendSummary])
async def trends(
    days: int = Query(default=30, ge=7, le=365),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WeightTrendSummary]:
    timezone = await DailyNutritionService(session).timezone(user.id)
    today = datetime.now(timezone).date()
    logs = await WeightRepository(session).list_for_user(
        user.id, date_from=today - timedelta(days=days - 1), date_to=today
    )
    return DataResponse(data=build_weight_trend(logs, today=today))


@router.get("", response_model=DataResponse[list[WeightRead]])
async def list_weights(
    date_from: date | None = Query(default=None, alias="from"),
    date_to: date | None = Query(default=None, alias="to"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[WeightRead]]:
    logs = await WeightRepository(session).list_for_user(user.id, date_from, date_to)
    return DataResponse(data=[WeightRead.model_validate(item) for item in reversed(logs)])


@router.post("", response_model=DataResponse[WeightRead], status_code=status.HTTP_201_CREATED)
async def create_weight(
    payload: WeightCreate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WeightRead]:
    log = await WeightService(session).create(user.id, payload)
    return DataResponse(data=WeightRead.model_validate(log))


@router.patch("/{log_id}", response_model=DataResponse[WeightRead])
async def update_weight(
    log_id: UUID,
    payload: WeightUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WeightRead]:
    log = await WeightService(session).update(user.id, log_id, payload)
    return DataResponse(data=WeightRead.model_validate(log))


@router.delete("/{log_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_weight(
    log_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await WeightService(session).delete(user.id, log_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
