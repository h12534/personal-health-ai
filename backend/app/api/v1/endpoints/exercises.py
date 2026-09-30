from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.training import ExerciseRead
from app.services.exercise_service import ExerciseService

router = APIRouter()


@router.get("", response_model=DataResponse[list[ExerciseRead]])
async def list_exercises(
    movement_pattern: str | None = Query(default=None, max_length=32),
    equipment: str | None = Query(default=None, max_length=32),
    difficulty: str | None = Query(default=None, max_length=24),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[ExerciseRead]]:
    items = await ExerciseService(session).list_all(
        movement_pattern=movement_pattern,
        equipment=equipment,
        difficulty=difficulty,
    )
    return DataResponse(
        data=[ExerciseRead.model_validate(item) for item in items],
        meta={"count": len(items)},
    )


@router.get("/search", response_model=DataResponse[list[ExerciseRead]])
async def search_exercises(
    query: str = Query(alias="q", min_length=1, max_length=120),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[ExerciseRead]]:
    items = await ExerciseService(session).search(query)
    return DataResponse(
        data=[ExerciseRead.model_validate(item) for item in items],
        meta={"count": len(items), "query": query},
    )
