from datetime import date
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Response, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user, get_lab_ocr_provider, get_private_storage
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.user import User
from app.providers.ai.base import LabOCRProvider
from app.providers.storage.base import StorageProvider
from app.schemas.common import DataResponse
from app.schemas.health_knowledge import (
    HealthCheckSuggestionRead,
    LabConfirmRequest,
    LabOCRItemPatch,
    LabReportRead,
    LabTrendRead,
)
from app.services.health_check_recommendation_service import HealthCheckRecommendationService
from app.services.lab_report_service import LabReportService, LabTrendService

router = APIRouter()


def _service(
    session: AsyncSession,
    settings: Settings,
    provider: LabOCRProvider,
    storage: StorageProvider,
) -> LabReportService:
    return LabReportService(session, settings, provider, storage)


@router.post(
    "/reports",
    response_model=DataResponse[LabReportRead],
    status_code=status.HTTP_201_CREATED,
)
async def upload_lab_report(
    file: UploadFile = File(...),
    report_date: date = Form(...),
    hospital_name: str | None = Form(default=None, max_length=240),
    source_type: Literal["camera", "photos", "files"] = Form(default="files"),
    retain_original: bool = Form(default=True),
    allow_remote_ocr: bool = Form(default=False),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: LabOCRProvider = Depends(get_lab_ocr_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[LabReportRead]:
    data = await file.read(settings.knowledge_max_upload_bytes + 1)
    report = await _service(session, settings, provider, storage).create(
        user.id,
        data=data,
        filename=file.filename or "lab-report",
        content_type=(file.content_type or "application/octet-stream").lower(),
        report_date=report_date,
        hospital_name=hospital_name,
        source_type=source_type,
        retain_original=retain_original,
        allow_remote_ocr=allow_remote_ocr,
    )
    return DataResponse(data=report)


@router.get("/reports", response_model=DataResponse[list[LabReportRead]])
async def list_lab_reports(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: LabOCRProvider = Depends(get_lab_ocr_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[list[LabReportRead]]:
    values = await _service(session, settings, provider, storage).list_all(user.id)
    return DataResponse(data=values, meta={"count": len(values)})


@router.get("/reports/{report_id}", response_model=DataResponse[LabReportRead])
async def get_lab_report(
    report_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: LabOCRProvider = Depends(get_lab_ocr_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[LabReportRead]:
    value = await _service(session, settings, provider, storage).read(user.id, report_id)
    return DataResponse(data=value)


@router.patch(
    "/reports/{report_id}/draft-items/{item_id}", response_model=DataResponse[LabReportRead]
)
async def patch_lab_draft_item(
    report_id: UUID,
    item_id: UUID,
    payload: LabOCRItemPatch,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: LabOCRProvider = Depends(get_lab_ocr_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[LabReportRead]:
    value = await _service(session, settings, provider, storage).patch_item(
        user.id, report_id, item_id, payload
    )
    return DataResponse(data=value)


@router.post("/reports/{report_id}/confirm", response_model=DataResponse[LabReportRead])
async def confirm_lab_report(
    report_id: UUID,
    payload: LabConfirmRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: LabOCRProvider = Depends(get_lab_ocr_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[LabReportRead]:
    value = await _service(session, settings, provider, storage).confirm(
        user.id, report_id, payload
    )
    return DataResponse(data=value)


@router.delete("/reports/{report_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_lab_report(
    report_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: LabOCRProvider = Depends(get_lab_ocr_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> Response:
    await _service(session, settings, provider, storage).delete(user.id, report_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/results/{result_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_lab_result(
    result_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    provider: LabOCRProvider = Depends(get_lab_ocr_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> Response:
    await _service(session, settings, provider, storage).delete_result(user.id, result_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/trends/{normalized_name}", response_model=DataResponse[LabTrendRead])
async def lab_trend(
    normalized_name: str,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[LabTrendRead]:
    return DataResponse(data=await LabTrendService(session).build(user.id, normalized_name))


@router.post(
    "/reports/{report_id}/follow-up-suggestions",
    response_model=DataResponse[list[HealthCheckSuggestionRead]],
)
async def create_follow_up_suggestions(
    report_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[HealthCheckSuggestionRead]]:
    values = await HealthCheckRecommendationService(session).generate(user.id, report_id)
    return DataResponse(data=[HealthCheckSuggestionRead.model_validate(value) for value in values])


@router.post(
    "/follow-up-suggestions/{suggestion_id}/accept",
    response_model=DataResponse[HealthCheckSuggestionRead],
)
async def accept_follow_up_suggestion(
    suggestion_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HealthCheckSuggestionRead]:
    value = await HealthCheckRecommendationService(session).accept(user.id, suggestion_id)
    return DataResponse(data=HealthCheckSuggestionRead.model_validate(value))
