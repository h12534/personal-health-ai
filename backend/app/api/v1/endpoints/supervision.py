from datetime import UTC, date, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_user,
    get_health_answer_provider,
    get_private_storage,
    get_push_provider,
)
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.supervision import NotificationLog, PushDevice
from app.models.user import User
from app.providers.ai.base import HealthAnswerProvider
from app.providers.push.base import PushProvider
from app.providers.storage.base import StorageProvider
from app.schemas.common import DataResponse
from app.schemas.supervision import (
    CrossDomainRead,
    DailyTaskRead,
    DeleteMyDataRequest,
    ExportBundleRead,
    HealthFollowupCreate,
    HealthFollowupRead,
    HealthReportRead,
    NotificationLogRead,
    PushDeviceUpsert,
    ReminderDecisionRead,
    ReminderPreferenceRead,
    ReminderPreferenceUpdate,
    TaskStatusUpdate,
    TimelineEventRead,
)
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.daily_task_service import DailyTaskEngine, ReminderPreferenceService
from app.services.followup_service import FollowupService
from app.services.health_report_service import HealthReportService
from app.services.health_timeline_service import CorrelationGuard, HealthTimelineService
from app.services.personal_data_service import PersonalDataService
from app.services.reminder_service import NotificationService, ReminderEngine

router = APIRouter()


class ReportGenerateRequest(BaseModel):
    report_type: str = Field(pattern="^(daily|weekly|monthly)$")
    reference_date: date | None = None
    force: bool = False


class FollowupDateUpdate(BaseModel):
    recommended_date: date


class CausalityQuestion(BaseModel):
    question: str = Field(min_length=2, max_length=1000)


@router.get("/tasks", response_model=DataResponse[list[DailyTaskRead]])
async def daily_tasks(
    on_date: date | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[DailyTaskRead]]:
    service = DailyTaskEngine(session)
    timezone = await DailyNutritionService(session).timezone(user.id)
    reference = on_date or datetime.now(timezone).date()
    tasks = await service.generate(user.id, reference)
    return DataResponse(data=[service.read(item) for item in tasks])


@router.post("/tasks/generate", response_model=DataResponse[list[DailyTaskRead]])
async def generate_daily_tasks(
    on_date: date | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[DailyTaskRead]]:
    service = DailyTaskEngine(session)
    values = await service.generate(user.id, on_date)
    return DataResponse(data=[service.read(item) for item in values])


@router.patch("/tasks/{task_id}", response_model=DataResponse[DailyTaskRead])
async def update_daily_task(
    task_id: UUID,
    payload: TaskStatusUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DailyTaskRead]:
    service = DailyTaskEngine(session)
    value = await service.set_status(user.id, task_id, payload.status)
    return DataResponse(data=service.read(value))


@router.get("/preferences", response_model=DataResponse[ReminderPreferenceRead])
async def reminder_preferences(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[ReminderPreferenceRead]:
    return DataResponse(
        data=_preference_read(await ReminderPreferenceService(session).get(user.id))
    )


@router.put("/preferences", response_model=DataResponse[ReminderPreferenceRead])
async def update_reminder_preferences(
    payload: ReminderPreferenceUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[ReminderPreferenceRead]:
    value = await ReminderPreferenceService(session).update(user.id, payload)
    return DataResponse(data=_preference_read(value))


@router.post("/reminders/evaluate", response_model=DataResponse[list[ReminderDecisionRead]])
async def evaluate_reminders(
    send: bool = Query(default=False),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    push: PushProvider = Depends(get_push_provider),
) -> DataResponse[list[ReminderDecisionRead]]:
    timezone = await DailyNutritionService(session).timezone(user.id)
    reference = datetime.now(timezone).date()
    tasks = await DailyTaskEngine(session).generate(user.id, reference)
    preference = await ReminderPreferenceService(session).get(user.id)
    engine = ReminderEngine(session)
    sender = NotificationService(session, push)
    values: list[ReminderDecisionRead] = []
    for task in tasks:
        decision = await engine.decide(task, preference)
        values.append(decision)
        if send and decision.should_send:
            await sender.send(task, decision)
    return DataResponse(data=values)


@router.get("/notifications", response_model=DataResponse[list[NotificationLogRead]])
async def notification_logs(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[NotificationLogRead]]:
    values = list(
        (
            await session.scalars(
                select(NotificationLog)
                .where(NotificationLog.user_id == user.id)
                .order_by(NotificationLog.created_at.desc())
                .limit(100)
            )
        ).all()
    )
    return DataResponse(data=[_notification_read(item) for item in values])


@router.put("/push-device", response_model=DataResponse[dict[str, str]])
async def upsert_push_device(
    payload: PushDeviceUpsert,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[dict[str, str]]:
    value = await session.scalar(
        select(PushDevice).where(
            PushDevice.user_id == user.id, PushDevice.device_id == payload.device_id
        )
    )
    if value is None:
        value = PushDevice(
            user_id=user.id,
            device_id=payload.device_id,
            platform=payload.platform,
            environment=payload.environment,
            token=payload.token,
            active=True,
            last_seen_at=datetime.now(UTC),
        )
        session.add(value)
    else:
        value.platform = payload.platform
        value.environment = payload.environment
        value.token = payload.token
        value.active = True
        value.last_seen_at = datetime.now(UTC)
    await session.commit()
    return DataResponse(
        data={"id": str(value.id), "status": "active", "environment": value.environment}
    )


@router.get("/reports", response_model=DataResponse[list[HealthReportRead]])
async def health_reports(
    report_type: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    provider: HealthAnswerProvider = Depends(get_health_answer_provider),
    settings: Settings = Depends(get_settings),
) -> DataResponse[list[HealthReportRead]]:
    service = HealthReportService(session, provider, settings)
    values = await service.list_reports(user.id, report_type, limit=limit, offset=offset)
    return DataResponse(
        data=[service.read(item) for item in values],
        meta={"count": len(values), "limit": limit, "offset": offset},
    )


@router.post("/reports/generate", response_model=DataResponse[HealthReportRead])
async def generate_health_report(
    payload: ReportGenerateRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    provider: HealthAnswerProvider = Depends(get_health_answer_provider),
    settings: Settings = Depends(get_settings),
) -> DataResponse[HealthReportRead]:
    service = HealthReportService(session, provider, settings)
    value = await service.generate(
        user.id, payload.report_type, payload.reference_date, force=payload.force
    )
    return DataResponse(data=service.read(value))


@router.get("/timeline", response_model=DataResponse[list[TimelineEventRead]])
async def health_timeline(
    date_from: date = Query(alias="from"),
    date_to: date = Query(alias="to"),
    category: str = Query(default="all"),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[TimelineEventRead]]:
    values = await HealthTimelineService(session).list_events(
        user.id, date_from, date_to, category, limit=limit, offset=offset
    )
    return DataResponse(
        data=values,
        meta={"count": len(values), "limit": limit, "offset": offset},
    )


@router.get("/cross-domain", response_model=DataResponse[CrossDomainRead])
async def cross_domain_trends(
    date_from: date = Query(alias="from"),
    date_to: date = Query(alias="to"),
    metrics: list[str] = Query(),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[CrossDomainRead]:
    return DataResponse(
        data=await HealthTimelineService(session).cross_domain(user.id, date_from, date_to, metrics)
    )


@router.post("/correlation-guard", response_model=DataResponse[dict[str, str]])
async def correlation_guard(payload: CausalityQuestion) -> DataResponse[dict[str, str]]:
    return DataResponse(
        data={"answer": CorrelationGuard.answer_causality_question(payload.question)}
    )


@router.post(
    "/followups",
    response_model=DataResponse[HealthFollowupRead],
    status_code=status.HTTP_201_CREATED,
)
async def create_followup(
    payload: HealthFollowupCreate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HealthFollowupRead]:
    value = await FollowupService(session).create(user.id, payload)
    return DataResponse(data=_followup_read(value))


@router.get("/followups", response_model=DataResponse[list[HealthFollowupRead]])
async def health_followups(
    followup_status: str | None = Query(default=None, alias="status"),
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[list[HealthFollowupRead]]:
    values = await FollowupService(session).list(user.id, followup_status)
    return DataResponse(data=[_followup_read(item) for item in values])


@router.post("/followups/{followup_id}/confirm", response_model=DataResponse[HealthFollowupRead])
async def confirm_followup(
    followup_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HealthFollowupRead]:
    return DataResponse(
        data=_followup_read(await FollowupService(session).confirm(user.id, followup_id))
    )


@router.patch("/followups/{followup_id}", response_model=DataResponse[HealthFollowupRead])
async def update_followup_date(
    followup_id: UUID,
    payload: FollowupDateUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HealthFollowupRead]:
    value = await FollowupService(session).update_date(
        user.id, followup_id, payload.recommended_date
    )
    return DataResponse(data=_followup_read(value))


@router.post("/followups/{followup_id}/cancel", response_model=DataResponse[HealthFollowupRead])
async def cancel_followup(
    followup_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[HealthFollowupRead]:
    return DataResponse(
        data=_followup_read(await FollowupService(session).cancel(user.id, followup_id))
    )


@router.get("/export/json", response_model=ExportBundleRead)
async def export_json(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    storage: StorageProvider = Depends(get_private_storage),
) -> dict[str, object]:
    return await PersonalDataService(session, storage).export_json(user.id)


@router.get("/export/csv", response_class=PlainTextResponse)
async def export_csv(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    storage: StorageProvider = Depends(get_private_storage),
) -> PlainTextResponse:
    value = await PersonalDataService(session, storage).export_csv(user.id)
    return PlainTextResponse(
        value,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="personal-health-data.csv"'},
    )


@router.delete("/data", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_data(
    payload: DeleteMyDataRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    storage: StorageProvider = Depends(get_private_storage),
) -> Response:
    await PersonalDataService(session, storage).delete_all(user.id, payload.confirmation)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _preference_read(value) -> ReminderPreferenceRead:  # type: ignore[no-untyped-def]
    return ReminderPreferenceRead(
        enabled=value.enabled,
        mode=value.mode,
        weigh_time=value.weigh_time,
        meal_windows=value.meal_windows,
        training_reminder_time=value.training_reminder_time,
        sleep_reminder_time=value.sleep_reminder_time,
        step_check_time=value.step_check_time,
        do_not_disturb_start=value.do_not_disturb_start,
        do_not_disturb_end=value.do_not_disturb_end,
        weekly_report_day=value.weekly_report_day,
        monthly_report_day=value.monthly_report_day,
        local_notifications_enabled=value.local_notifications_enabled,
        server_notifications_enabled=value.server_notifications_enabled,
    )


def _followup_read(value) -> HealthFollowupRead:  # type: ignore[no-untyped-def]
    return HealthFollowupRead(
        id=value.id,
        lab_test_code=value.lab_test_code,
        reason=value.reason,
        recommended_date=value.recommended_date,
        status=value.status,
        source=value.source,
        source_entity_id=value.source_entity_id,
        confirmed_at=value.confirmed_at,
    )


def _notification_read(value: NotificationLog) -> NotificationLogRead:
    return NotificationLogRead(
        id=value.id,
        task_id=value.task_id,
        notification_type=value.notification_type,
        channel=value.channel,
        scheduled_at=value.scheduled_at,
        sent_at=value.sent_at,
        status=value.status,
        reason=value.reason,
        provider=value.provider,
        interaction=value.interaction,
    )
