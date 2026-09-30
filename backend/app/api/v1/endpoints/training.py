from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.training import (
    ExerciseProgressRead,
    PRRead,
    TrainingAdjustmentApply,
    TrainingExerciseRead,
    TrainingPlanCreate,
    TrainingPlanGenerate,
    TrainingPlanRead,
    TrainingPlanUpdate,
    WeeklyTrainingReviewRead,
)
from app.services.training_plan_service import TrainingPlanService
from app.services.weekly_training_review_service import WeeklyTrainingReviewService
from app.services.workout_service import WorkoutService

router = APIRouter()


@router.post(
    "/plans", response_model=DataResponse[TrainingPlanRead], status_code=status.HTTP_201_CREATED
)
async def create_plan(
    payload: TrainingPlanCreate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TrainingPlanRead]:
    plan = await TrainingPlanService(session).create(user.id, payload)
    return DataResponse(data=TrainingPlanRead.model_validate(plan))


@router.get("/plans", response_model=DataResponse[list[TrainingPlanRead]])
async def list_plans(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[TrainingPlanRead]]:
    plans = await TrainingPlanService(session).list_all(user.id)
    return DataResponse(
        data=[TrainingPlanRead.model_validate(item) for item in plans],
        meta={"count": len(plans)},
    )


@router.post(
    "/plans/generate",
    response_model=DataResponse[TrainingPlanRead],
    status_code=status.HTTP_201_CREATED,
)
async def generate_plan(
    payload: TrainingPlanGenerate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TrainingPlanRead]:
    plan = await TrainingPlanService(session).generate(user.id, payload)
    return DataResponse(data=TrainingPlanRead.model_validate(plan))


@router.get("/plans/{plan_id}", response_model=DataResponse[TrainingPlanRead])
async def get_plan(
    plan_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TrainingPlanRead]:
    plan = await TrainingPlanService(session).get(user.id, plan_id)
    return DataResponse(data=TrainingPlanRead.model_validate(plan))


@router.patch("/plans/{plan_id}", response_model=DataResponse[TrainingPlanRead])
async def update_plan(
    plan_id: UUID,
    payload: TrainingPlanUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TrainingPlanRead]:
    plan = await TrainingPlanService(session).update(user.id, plan_id, payload)
    return DataResponse(data=TrainingPlanRead.model_validate(plan))


@router.post("/adjustments/apply", response_model=DataResponse[TrainingExerciseRead])
async def apply_training_adjustment(
    payload: TrainingAdjustmentApply,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TrainingExerciseRead]:
    item = await TrainingPlanService(session).apply_progression(user.id, payload)
    return DataResponse(data=TrainingExerciseRead.model_validate(item))


@router.get("/progress/{exercise_id}", response_model=DataResponse[ExerciseProgressRead])
async def exercise_progress(
    exercise_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[ExerciseProgressRead]:
    return DataResponse(data=await WorkoutService(session).progress(user.id, exercise_id))


@router.get("/prs", response_model=DataResponse[list[PRRead]])
async def personal_records(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[PRRead]]:
    records = await WorkoutService(session).prs(user.id)
    return DataResponse(
        data=[PRRead.model_validate(item) for item in records],
        meta={"count": len(records)},
    )


@router.get("/weekly-review", response_model=DataResponse[WeeklyTrainingReviewRead])
async def weekly_training_review(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WeeklyTrainingReviewRead]:
    return DataResponse(data=await WeeklyTrainingReviewService(session).build(user.id))
