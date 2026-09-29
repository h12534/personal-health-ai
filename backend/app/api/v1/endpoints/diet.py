from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.diet_coach import HungerLog, PersonalDietaryMemory
from app.models.user import User
from app.repositories.diet_coach_repository import DietCoachRepository
from app.schemas.common import DataResponse
from app.schemas.diet_coach import (
    AdjustmentDecision,
    DailyTargetRead,
    DietAdherenceRead,
    DietAdjustmentRead,
    DietaryMemoryRead,
    DietaryMemoryWrite,
    EnergyModelRead,
    HungerLogRead,
    HungerLogWrite,
    MealRecommendationRead,
    NextMealPlanRead,
    WeeklyReviewRead,
    WeightTrendRead,
)
from app.services.diet_adherence_service import DietAdherenceService
from app.services.diet_adjustment_service import DietAdjustmentService
from app.services.meal_recommendation_service import MealRecommendationService
from app.services.next_meal_planner import NextMealPlanner
from app.services.nutrition_target_service import NutritionTargetService
from app.services.tdee_estimator import TDEEEstimator
from app.services.weekly_diet_review_service import WeeklyDietReviewService
from app.services.weight_trend_service import WeightTrendService
from app.utils.text import normalize_food_name

router = APIRouter()


@router.get("/targets/daily", response_model=DataResponse[DailyTargetRead])
async def daily_target(
    on_date: date | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DailyTargetRead]:
    return DataResponse(data=await NutritionTargetService(session).daily(user.id, on_date))


@router.get("/weight-trend", response_model=DataResponse[WeightTrendRead])
async def weight_trend(
    as_of: date | None = None,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WeightTrendRead]:
    adherence = await DietAdherenceService(session).calculate(user.id, as_of)
    return DataResponse(
        data=await WeightTrendService(session).build(user.id, as_of, adherence.overall_rate)
    )


@router.get("/adherence", response_model=DataResponse[DietAdherenceRead])
async def adherence(
    as_of: date | None = None,
    days: int = Query(default=14, ge=7, le=28),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DietAdherenceRead]:
    return DataResponse(data=await DietAdherenceService(session).calculate(user.id, as_of, days))


@router.get("/energy-model", response_model=DataResponse[EnergyModelRead])
async def energy_model(
    as_of: date | None = None,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[EnergyModelRead]:
    return DataResponse(data=await TDEEEstimator(session).estimate(user.id, as_of))


@router.get("/next-meal", response_model=DataResponse[NextMealPlanRead])
async def next_meal(
    on_date: date | None = Query(default=None, alias="date"),
    hour: int | None = Query(default=None, ge=0, le=23),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[NextMealPlanRead]:
    return DataResponse(data=await NextMealPlanner(session).plan(user.id, on_date, hour))


@router.get("/meal-recommendations", response_model=DataResponse[list[MealRecommendationRead]])
async def meal_recommendations(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[MealRecommendationRead]]:
    target = (await NextMealPlanner(session).plan(user.id)).target
    values = await MealRecommendationService(session).recommend(user.id, target)
    return DataResponse(data=values)


@router.get("/weekly-review", response_model=DataResponse[WeeklyReviewRead])
async def weekly_review(
    as_of: date | None = None,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WeeklyReviewRead]:
    return DataResponse(data=await WeeklyDietReviewService(session).build(user.id, as_of))


@router.get("/adjustments/current", response_model=DataResponse[DietAdjustmentRead | None])
async def current_adjustment(
    as_of: date | None = None,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DietAdjustmentRead | None]:
    value = await DietAdjustmentService(session).suggest(user.id, as_of)
    return DataResponse(data=DietAdjustmentRead.model_validate(value) if value else None)


@router.post("/adjustments/{adjustment_id}/accept", response_model=DataResponse[DietAdjustmentRead])
async def accept_adjustment(
    adjustment_id: UUID,
    payload: AdjustmentDecision,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DietAdjustmentRead]:
    value = await DietAdjustmentService(session).accept(
        user.id, adjustment_id, payload.idempotency_key
    )
    return DataResponse(data=DietAdjustmentRead.model_validate(value))


@router.post(
    "/adjustments/{adjustment_id}/decline", response_model=DataResponse[DietAdjustmentRead]
)
async def decline_adjustment(
    adjustment_id: UUID,
    payload: AdjustmentDecision,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DietAdjustmentRead]:
    value = await DietAdjustmentService(session).decline(
        user.id, adjustment_id, payload.idempotency_key
    )
    return DataResponse(data=DietAdjustmentRead.model_validate(value))


@router.post(
    "/hunger", response_model=DataResponse[HungerLogRead], status_code=status.HTTP_201_CREATED
)
async def log_hunger(
    payload: HungerLogWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HungerLogRead]:
    value = HungerLog(
        user_id=user.id,
        logged_at=(payload.logged_at or datetime.now(UTC)).astimezone(UTC),
        hunger_level=payload.hunger_level,
        craving_level=payload.craving_level,
        context=payload.context,
        note=payload.note,
    )
    session.add(value)
    await session.commit()
    await session.refresh(value)
    return DataResponse(data=HungerLogRead.model_validate(value))


@router.get("/hunger", response_model=DataResponse[list[HungerLogRead]])
async def list_hunger(
    limit: int = Query(default=30, ge=1, le=100),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[HungerLogRead]]:
    values = await DietCoachRepository(session).hunger_logs(user.id, limit)
    return DataResponse(data=[HungerLogRead.model_validate(value) for value in values])


@router.post(
    "/memories", response_model=DataResponse[DietaryMemoryRead], status_code=status.HTTP_201_CREATED
)
async def create_memory(
    payload: DietaryMemoryWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DietaryMemoryRead]:
    value = PersonalDietaryMemory(
        user_id=user.id,
        kind=payload.kind,
        memory_key=payload.key,
        value=payload.value.strip(),
        normalized_value=normalize_food_name(payload.value),
        confidence=Decimal("1"),
        source="explicit_user_statement",
        last_confirmed_at=datetime.now(UTC),
    )
    session.add(value)
    await session.commit()
    await session.refresh(value)
    return DataResponse(data=DietaryMemoryRead.model_validate(value))


@router.get("/memories", response_model=DataResponse[list[DietaryMemoryRead]])
async def list_memories(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[DietaryMemoryRead]]:
    values = await DietCoachRepository(session).memories(user.id)
    return DataResponse(data=[DietaryMemoryRead.model_validate(value) for value in values])


@router.patch("/memories/{memory_id}", response_model=DataResponse[DietaryMemoryRead])
async def update_memory(
    memory_id: UUID,
    payload: DietaryMemoryWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DietaryMemoryRead]:
    value = await DietCoachRepository(session).memory(user.id, memory_id)
    if value is None:
        from app.core.errors import AppError

        raise AppError("memory_not_found", "Dietary memory was not found.", 404)
    value.kind = payload.kind
    value.memory_key = payload.key
    value.value = payload.value.strip()
    value.normalized_value = normalize_food_name(payload.value)
    value.confidence = Decimal("1")
    value.source = "explicit_user_statement"
    value.last_confirmed_at = datetime.now(UTC)
    await session.commit()
    await session.refresh(value)
    return DataResponse(data=DietaryMemoryRead.model_validate(value))


@router.delete("/memories/{memory_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_memory(
    memory_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    value = await DietCoachRepository(session).memory(user.id, memory_id)
    if value is None:
        from app.core.errors import AppError

        raise AppError("memory_not_found", "Dietary memory was not found.", 404)
    value.is_active = False
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
