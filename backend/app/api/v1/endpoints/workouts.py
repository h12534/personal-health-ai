from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.training import (
    PainLogWrite,
    WorkoutComplete,
    WorkoutSessionCreate,
    WorkoutSessionRead,
    WorkoutSetCreate,
    WorkoutSetRead,
    WorkoutSetUpdate,
    WorkoutSummary,
)
from app.services.workout_service import WorkoutService

router = APIRouter()


@router.post("", response_model=DataResponse[WorkoutSessionRead], status_code=201)
async def create_workout(
    payload: WorkoutSessionCreate,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WorkoutSessionRead]:
    workout = await WorkoutService(session).create(user.id, payload, idempotency_key)
    return DataResponse(data=WorkoutSessionRead.model_validate(workout))


@router.get("", response_model=DataResponse[list[WorkoutSessionRead]])
async def list_workouts(
    date_from: date | None = Query(default=None, alias="from"),
    date_to: date | None = Query(default=None, alias="to"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[WorkoutSessionRead]]:
    workouts = await WorkoutService(session).list_all(user.id, date_from, date_to)
    return DataResponse(
        data=[WorkoutSessionRead.model_validate(item) for item in workouts],
        meta={"count": len(workouts)},
    )


@router.get("/{workout_id}", response_model=DataResponse[WorkoutSessionRead])
async def get_workout(
    workout_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WorkoutSessionRead]:
    workout = await WorkoutService(session).get(user.id, workout_id)
    return DataResponse(data=WorkoutSessionRead.model_validate(workout))


@router.post(
    "/{workout_id}/sets",
    response_model=DataResponse[WorkoutSetRead],
    status_code=status.HTTP_201_CREATED,
)
async def add_workout_set(
    workout_id: UUID,
    payload: WorkoutSetCreate,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WorkoutSetRead]:
    item = await WorkoutService(session).add_set(user.id, workout_id, payload, idempotency_key)
    return DataResponse(data=WorkoutSetRead.model_validate(item))


@router.patch("/{workout_id}/sets/{set_id}", response_model=DataResponse[WorkoutSetRead])
async def update_workout_set(
    workout_id: UUID,
    set_id: UUID,
    payload: WorkoutSetUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WorkoutSetRead]:
    item = await WorkoutService(session).update_set(user.id, workout_id, set_id, payload)
    return DataResponse(data=WorkoutSetRead.model_validate(item))


@router.post("/{workout_id}/complete", response_model=DataResponse[WorkoutSummary])
async def complete_workout(
    workout_id: UUID,
    payload: WorkoutComplete,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[WorkoutSummary]:
    return DataResponse(data=await WorkoutService(session).complete(user.id, workout_id, payload))


@router.post("/{workout_id}/pain", status_code=status.HTTP_201_CREATED)
async def log_pain(
    workout_id: UUID,
    payload: PainLogWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[dict[str, object]]:
    values = payload.model_copy(update={"workout_session_id": workout_id})
    item = await WorkoutService(session).log_pain(user.id, values)
    return DataResponse(
        data={
            "id": item.id,
            "severity": item.severity,
            "safety_escalation": item.severity >= 7 or item.acute,
        }
    )
