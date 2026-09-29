from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Header, Response, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_user,
    get_private_storage,
    get_vision_provider,
)
from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.db.session import get_db
from app.models.user import User
from app.providers.ai.base import VisionProvider
from app.providers.storage.base import StorageProvider
from app.schemas.common import DataResponse
from app.schemas.meal import MealRead, MealType
from app.schemas.meal_analysis import (
    MealAnalysisConfirm,
    MealAnalysisItemCreate,
    MealAnalysisItemPatch,
    MealAnalysisRead,
)
from app.services.meal_analysis_service import MealAnalysisService

router = APIRouter()


def _service(
    session: AsyncSession,
    settings: Settings,
    provider: VisionProvider,
    storage: StorageProvider,
) -> MealAnalysisService:
    return MealAnalysisService(session, settings, provider, storage)


async def _dispatch_or_process(
    service: MealAnalysisService, analysis_id: UUID, settings: Settings
) -> None:
    if settings.vision_async_enabled:
        from app.jobs.meal_analysis_tasks import process_meal_analysis

        try:
            process_meal_analysis.delay(str(analysis_id))
        except Exception as exc:
            raise AppError(
                "analysis_dispatch_failed",
                "Meal analysis could not be queued. Please retry shortly.",
                503,
            ) from exc
    else:
        await service.process(analysis_id)


@router.post(
    "/meals/analyze-image",
    response_model=DataResponse[MealAnalysisRead],
    status_code=status.HTTP_202_ACCEPTED,
)
async def analyze_meal_image(
    image: UploadFile = File(...),
    location_context: str | None = Form(default=None, max_length=100),
    meal_type: MealType | None = Form(default=None),
    eaten_at: datetime | None = Form(default=None),
    note: str | None = Form(default=None, max_length=4000),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: VisionProvider = Depends(get_vision_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[MealAnalysisRead]:
    if eaten_at is not None and (eaten_at.tzinfo is None or eaten_at.utcoffset() is None):
        raise AppError("timezone_required", "eaten_at must include a timezone offset.", 422)
    data = await image.read(settings.max_upload_bytes + 1)
    service = _service(session, settings, provider, storage)
    created = await service.create(
        user.id,
        data,
        image.content_type,
        idempotency_key,
        location_context,
        meal_type,
        eaten_at,
        note,
    )
    if created.status == "pending":
        await _dispatch_or_process(service, created.id, settings)
    return DataResponse(data=await service.get(user.id, created.id))


@router.get("/meals/analyses/{analysis_id}", response_model=DataResponse[MealAnalysisRead])
async def get_meal_analysis(
    analysis_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: VisionProvider = Depends(get_vision_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[MealAnalysisRead]:
    service = _service(session, settings, provider, storage)
    return DataResponse(data=await service.get(user.id, analysis_id))


@router.patch(
    "/meals/analyses/{analysis_id}/items/{item_id}",
    response_model=DataResponse[MealAnalysisRead],
)
async def patch_meal_analysis_item(
    analysis_id: UUID,
    item_id: UUID,
    payload: MealAnalysisItemPatch,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: VisionProvider = Depends(get_vision_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[MealAnalysisRead]:
    service = _service(session, settings, provider, storage)
    return DataResponse(data=await service.patch_item(user.id, analysis_id, item_id, payload))


@router.post(
    "/meals/analyses/{analysis_id}/items",
    response_model=DataResponse[MealAnalysisRead],
    status_code=status.HTTP_201_CREATED,
)
async def add_meal_analysis_item(
    analysis_id: UUID,
    payload: MealAnalysisItemCreate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: VisionProvider = Depends(get_vision_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[MealAnalysisRead]:
    service = _service(session, settings, provider, storage)
    return DataResponse(data=await service.add_item(user.id, analysis_id, payload))


@router.delete(
    "/meals/analyses/{analysis_id}/items/{item_id}",
    response_model=DataResponse[MealAnalysisRead],
)
async def delete_meal_analysis_item(
    analysis_id: UUID,
    item_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: VisionProvider = Depends(get_vision_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[MealAnalysisRead]:
    service = _service(session, settings, provider, storage)
    return DataResponse(data=await service.delete_item(user.id, analysis_id, item_id))


@router.post(
    "/meals/analyses/{analysis_id}/reanalyze",
    response_model=DataResponse[MealAnalysisRead],
    status_code=status.HTTP_202_ACCEPTED,
)
async def reanalyze_meal_image(
    analysis_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: VisionProvider = Depends(get_vision_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[MealAnalysisRead]:
    service = _service(session, settings, provider, storage)
    await service.prepare_reanalysis(user.id, analysis_id)
    await _dispatch_or_process(service, analysis_id, settings)
    return DataResponse(data=await service.get(user.id, analysis_id))


@router.delete("/meals/analyses/{analysis_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_meal_analysis(
    analysis_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: VisionProvider = Depends(get_vision_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> Response:
    service = _service(session, settings, provider, storage)
    await service.delete(user.id, analysis_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/meals/analyses/{analysis_id}/confirm",
    response_model=DataResponse[MealRead],
    status_code=status.HTTP_201_CREATED,
)
async def confirm_meal_analysis(
    analysis_id: UUID,
    payload: MealAnalysisConfirm,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: VisionProvider = Depends(get_vision_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[MealRead]:
    service = _service(session, settings, provider, storage)
    meal = await service.confirm(user.id, analysis_id, payload, idempotency_key)
    return DataResponse(data=meal)
