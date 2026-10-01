from datetime import date

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.health_activity import HealthSyncState
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.health_activity import (
    DailyActivityRead,
    HealthSummaryWrite,
    HealthSyncResult,
    HealthSyncStatusRead,
    PermissionRead,
    PermissionWrite,
    RecoveryInput,
    RecoveryRead,
    SleepRead,
)
from app.services.health_activity_service import HealthActivityService
from app.services.recovery_service import RecoveryService

activity_router = APIRouter()
sleep_router = APIRouter()
recovery_router = APIRouter()
health_router = APIRouter()


@activity_router.get("/daily", response_model=DataResponse[DailyActivityRead])
async def daily_activity(
    on_date: date | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DailyActivityRead]:
    return DataResponse(data=await HealthActivityService(session).daily(user.id, on_date))


@sleep_router.get("", response_model=DataResponse[list[SleepRead]])
async def sleep_logs(
    date_from: date | None = Query(default=None, alias="from"),
    date_to: date | None = Query(default=None, alias="to"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[SleepRead]]:
    items = await HealthActivityService(session).sleep(user.id, date_from, date_to)
    return DataResponse(
        data=[SleepRead.model_validate(item) for item in items],
        meta={"count": len(items)},
    )


@recovery_router.get("/today", response_model=DataResponse[RecoveryRead])
async def recovery_today(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[RecoveryRead]:
    return DataResponse(data=await RecoveryService(session).today(user.id))


@recovery_router.post("/today", response_model=DataResponse[RecoveryRead])
async def update_recovery_today(
    payload: RecoveryInput,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[RecoveryRead]:
    return DataResponse(data=await RecoveryService(session).today(user.id, payload))


@health_router.post("/sync/summary", response_model=DataResponse[HealthSyncResult])
async def sync_health_summary(
    payload: HealthSummaryWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HealthSyncResult]:
    return DataResponse(data=await HealthActivityService(session).sync_summary(user.id, payload))


@health_router.get("/permissions", response_model=DataResponse[list[PermissionRead]])
async def health_permissions(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[PermissionRead]]:
    return DataResponse(data=await HealthActivityService(session).permissions(user.id))


@health_router.get("/sync/status", response_model=DataResponse[list[HealthSyncStatusRead]])
async def health_sync_status(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[HealthSyncStatusRead]]:
    values = list(
        (
            await session.scalars(
                select(HealthSyncState)
                .where(
                    HealthSyncState.user_id == user.id,
                    HealthSyncState.provider == "healthkit",
                )
                .order_by(HealthSyncState.data_type)
            )
        ).all()
    )
    return DataResponse(
        data=[
            HealthSyncStatusRead(
                data_type=item.data_type,
                last_sync_at=item.last_sync_at,
                status=item.status,
                error_summary=item.error_summary,
            )
            for item in values
        ]
    )


@health_router.put("/permissions", response_model=DataResponse[PermissionRead])
async def set_health_permission(
    payload: PermissionWrite,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[PermissionRead]:
    return DataResponse(data=await HealthActivityService(session).set_permission(user.id, payload))


@health_router.delete("/sync/{provider}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_health_data(
    provider: str,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await HealthActivityService(session).delete_provider_data(user.id, provider)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
