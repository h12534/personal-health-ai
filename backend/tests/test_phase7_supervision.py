from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID

from httpx import AsyncClient
from sqlalchemy import func, select

from app.api.dependencies import get_private_storage
from app.core.config import Settings
from app.db.session import SessionLocal
from app.main import app
from app.models.health_activity import SleepLog, StepLog
from app.models.meal import MealLog
from app.models.supervision import (
    DailyTask,
    HealthFollowup,
    NotificationLog,
    PushDevice,
)
from app.models.user import User
from app.models.weight_log import WeightLog
from app.providers.ai.health_answer import MockHealthAnswerProvider
from app.providers.push.mock import MockPushProvider
from app.providers.storage.local import LocalStorageProvider
from app.schemas.supervision import ReminderDecisionRead
from app.services.daily_task_service import ReminderPreferenceService
from app.services.health_report_service import HealthReportService, ProactiveCoachService
from app.services.health_timeline_service import CorrelationGuard, HealthTimelineService
from app.services.reminder_service import (
    NotificationPrivacy,
    NotificationService,
    ReminderCopy,
    ReminderEngine,
)

REFERENCE = date(2026, 10, 1)


async def _user_id() -> UUID:
    async with SessionLocal() as session:
        value = await session.scalar(select(User.id).where(User.email == "owner@example.com"))
        assert value is not None
        return value


async def test_daily_task_generation_dedup_and_auto_completion(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    response = await client.post(
        "/api/v1/supervision/tasks/generate",
        params={"date": REFERENCE.isoformat()},
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text
    first = response.json()["data"]
    assert {item["task_type"] for item in first} >= {
        "weigh_in",
        "breakfast_log",
        "lunch_log",
        "dinner_log",
        "nutrition_target",
        "steps",
        "water",
        "sleep",
    }
    replay = await client.post(
        "/api/v1/supervision/tasks/generate",
        params={"date": REFERENCE.isoformat()},
        headers=auth_headers,
    )
    assert {item["id"] for item in replay.json()["data"]} == {item["id"] for item in first}

    user_id = await _user_id()
    async with SessionLocal() as session:
        session.add_all(
            [
                WeightLog(
                    user_id=user_id,
                    measured_on=REFERENCE,
                    weight_kg=Decimal("98.4"),
                    source="manual",
                ),
                MealLog(
                    user_id=user_id,
                    meal_type="lunch",
                    eaten_at=datetime(2026, 10, 1, 4, 0, tzinfo=UTC),
                    source="manual",
                    total_calories=Decimal("600"),
                    total_protein=Decimal("35"),
                    total_carbs=Decimal("70"),
                    total_fat=Decimal("18"),
                    total_fiber=Decimal("8"),
                ),
                StepLog(
                    user_id=user_id,
                    step_date=REFERENCE,
                    steps=8000,
                    source="manual",
                    source_record_id="phase7-steps",
                ),
            ]
        )
        await session.commit()
    refreshed = await client.get(
        "/api/v1/supervision/tasks",
        params={"date": REFERENCE.isoformat()},
        headers=auth_headers,
    )
    by_type = {item["task_type"]: item for item in refreshed.json()["data"]}
    assert by_type["weigh_in"]["status"] == "completed"
    assert by_type["lunch_log"]["status"] == "completed"
    assert by_type["steps"]["status"] == "completed"
    manual = await client.patch(
        f"/api/v1/supervision/tasks/{by_type['water']['id']}",
        json={"status": "skipped"},
        headers=auth_headers,
    )
    assert manual.json()["data"]["status"] == "skipped"


async def test_reminder_preferences_dnd_cooldown_and_privacy(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    updated = await client.put(
        "/api/v1/supervision/preferences",
        headers=auth_headers,
        json={
            "enabled": True,
            "mode": "gentle",
            "weigh_time": "08:00:00",
            "meal_windows": {
                "breakfast": ["07:00", "10:00"],
                "lunch": ["11:00", "14:00"],
                "dinner": ["17:00", "21:00"],
            },
            "training_reminder_time": "18:00:00",
            "sleep_reminder_time": "23:00:00",
            "step_check_time": "20:00:00",
            "do_not_disturb_start": "23:00:00",
            "do_not_disturb_end": "07:30:00",
            "weekly_report_day": 6,
            "monthly_report_day": 1,
            "local_notifications_enabled": True,
            "server_notifications_enabled": True,
        },
    )
    assert updated.status_code == 200
    assert updated.json()["data"]["mode"] == "gentle"

    async with SessionLocal() as session:
        task = DailyTask(
            user_id=await _user_id(),
            task_date=REFERENCE,
            task_type="lab_recheck",
            title="HbA1c 复查",
            description="敏感数值 5.9",
            status="pending",
            priority=100,
            scheduled_time=time(9),
            source="test",
            reminder_policy={"channel": "server", "sensitive": True},
            dedup_key="lab:test",
        )
        session.add(task)
        await session.commit()
        redacted = NotificationPrivacy.redact(task, ReminderCopy(task.title, task.description))
        assert redacted.title == "健康提醒"
        assert "5.9" not in redacted.body
        preference = await ReminderPreferenceService(session).get(task.user_id)
        preference.mode = "standard"
        preference.do_not_disturb_start = time(8, 30)
        preference.do_not_disturb_end = time(9, 30)
        await session.commit()
        now = datetime(2026, 10, 1, 1, 0, tzinfo=UTC)
        dnd = await ReminderEngine(session).decide(task, preference, now=now)
        assert dnd.reason == "do_not_disturb"
        preference.do_not_disturb_start = time(23)
        preference.do_not_disturb_end = time(7, 30)
        await session.commit()
        due = await ReminderEngine(session).decide(task, preference, now=now)
        assert due.should_send is True
        session.add(
            NotificationLog(
                user_id=task.user_id,
                task_id=task.id,
                notification_type=task.task_type,
                channel="server",
                scheduled_at=now - timedelta(hours=1),
                sent_at=now - timedelta(hours=1),
                status="sent",
                provider="mock",
                dedup_key="cooldown-test",
            )
        )
        await session.commit()
        cooldown = await ReminderEngine(session).decide(task, preference, now=now)
        assert cooldown.reason == "cooldown"

    guard = await client.post(
        "/api/v1/supervision/correlation-guard",
        headers=auth_headers,
        json={"question": "是不是因为减肥 HbA1c 才下降？"},
    )
    assert "不能确认因果" in guard.json()["data"]["answer"]
    assert "相关不等于因果" in CorrelationGuard.DISCLAIMER


async def test_push_mock_dedup_failure_retry_and_safe_payload(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    del client, auth_headers
    user_id = await _user_id()
    async with SessionLocal() as session:
        task = DailyTask(
            user_id=user_id,
            task_date=REFERENCE,
            task_type="lab_recheck",
            title="具体疾病复查",
            description="HbA1c 5.9",
            status="pending",
            priority=100,
            scheduled_time=time(9),
            source="test",
            reminder_policy={"channel": "server", "sensitive": True},
            dedup_key="lab:push",
        )
        session.add(task)
        session.add(
            PushDevice(
                user_id=user_id,
                device_id="iphone-beta-1",
                platform="ios",
                token="mock-device-token",
                active=True,
                last_seen_at=datetime.now(UTC),
            )
        )
        await session.commit()
        decision = ReminderDecisionRead(
            should_send=True,
            reason="due",
            channel="server",
            title="健康提醒",
            body="你有一项健康复查提醒。",
            task_id=task.id,
        )
        failed_provider = MockPushProvider(fail=True)
        failed = await NotificationService(session, failed_provider).send(task, decision)
        assert failed.status == "failed"
        success_provider = MockPushProvider()
        retried = await NotificationService(session, success_provider).send(task, decision)
        assert retried.id == failed.id
        assert retried.status == "sent"
        assert success_provider.messages[0].body == "你有一项健康复查提醒。"
        duplicate = await NotificationService(session, success_provider).send(task, decision)
        assert duplicate.id == failed.id
        count = await session.scalar(select(func.count(NotificationLog.id)))
        assert count == 1


async def test_followup_confirmation_creates_due_task(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    created = await client.post(
        "/api/v1/supervision/followups",
        headers=auth_headers,
        json={
            "lab_test_code": "HBA1C",
            "reason": "与医生讨论后安排三个月复查",
            "recommended_date": REFERENCE.isoformat(),
        },
    )
    assert created.status_code == 201
    followup_id = created.json()["data"]["id"]
    suggested_tasks = await client.get(
        "/api/v1/supervision/tasks",
        params={"date": REFERENCE.isoformat()},
        headers=auth_headers,
    )
    assert "lab_recheck" not in {item["task_type"] for item in suggested_tasks.json()["data"]}
    confirmed = await client.post(
        f"/api/v1/supervision/followups/{followup_id}/confirm", headers=auth_headers
    )
    assert confirmed.json()["data"]["status"] == "confirmed"
    due_tasks = await client.get(
        "/api/v1/supervision/tasks",
        params={"date": REFERENCE.isoformat()},
        headers=auth_headers,
    )
    lab_task = next(item for item in due_tasks.json()["data"] if item["task_type"] == "lab_recheck")
    assert lab_task["source_entity_id"] == followup_id


async def test_reports_timeline_and_proactive_limit(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    user_id = await _user_id()
    async with SessionLocal() as session:
        session.add_all(
            [
                WeightLog(
                    user_id=user_id,
                    measured_on=REFERENCE,
                    weight_kg=Decimal("98.0"),
                    source="manual",
                ),
                MealLog(
                    user_id=user_id,
                    meal_type="dinner",
                    eaten_at=datetime(2026, 10, 1, 10, 0, tzinfo=UTC),
                    source="manual",
                    total_calories=Decimal("650"),
                    total_protein=Decimal("42"),
                    total_carbs=Decimal("70"),
                    total_fat=Decimal("20"),
                    total_fiber=Decimal("9"),
                ),
                StepLog(
                    user_id=user_id,
                    step_date=REFERENCE,
                    steps=7200,
                    source="manual",
                    source_record_id="timeline-steps",
                ),
            ]
        )
        for offset in range(7):
            current = REFERENCE - timedelta(days=offset)
            session.add(
                SleepLog(
                    user_id=user_id,
                    sleep_start=datetime.combine(current - timedelta(days=1), time(23), UTC),
                    sleep_end=datetime.combine(current, time(5), UTC),
                    duration_min=360,
                    source="manual",
                    source_record_id=f"phase7-sleep-{current}",
                )
            )
        await session.commit()
        settings = Settings(proactive_ai_daily_limit=1)
        first = await ProactiveCoachService(session, settings).evaluate(user_id, REFERENCE)
        second = await ProactiveCoachService(session, settings).evaluate(user_id, REFERENCE)
        assert len(first) == 1
        assert second == []
        proactive_task = await session.scalar(
            select(DailyTask).where(
                DailyTask.user_id == user_id,
                DailyTask.source == "proactive_coach",
                DailyTask.task_date == REFERENCE,
            )
        )
        assert proactive_task is not None
        assert proactive_task.reminder_policy["cooldown_hours"] == 24

    reports: dict[str, dict[str, object]] = {}
    for report_type in ("daily", "weekly", "monthly"):
        response = await client.post(
            "/api/v1/supervision/reports/generate",
            headers=auth_headers,
            json={"report_type": report_type, "reference_date": REFERENCE.isoformat()},
        )
        assert response.status_code == 200, response.text
        reports[report_type] = response.json()["data"]
        assert "score" not in response.text.lower()
        assert response.json()["data"]["rule_version"] == "health_report_v1"
    cached = await client.post(
        "/api/v1/supervision/reports/generate",
        headers=auth_headers,
        json={"report_type": "daily", "reference_date": REFERENCE.isoformat()},
    )
    assert cached.json()["data"]["id"] == reports["daily"]["id"]

    timeline = await client.get(
        "/api/v1/supervision/timeline",
        params={"from": "2026-09-01", "to": "2026-10-31", "category": "all"},
        headers=auth_headers,
    )
    assert timeline.status_code == 200, timeline.text
    event_types = {item["event_type"] for item in timeline.json()["data"]}
    assert {"weight", "meal", "steps", "sleep", "health_report"} <= event_types
    trends = await client.get(
        "/api/v1/supervision/cross-domain",
        params=[
            ("from", "2026-09-01"),
            ("to", "2026-10-31"),
            ("metrics", "weight"),
            ("metrics", "steps"),
            ("metrics", "sleep"),
            ("metrics", "hba1c"),
        ],
        headers=auth_headers,
    )
    assert trends.status_code == 200
    assert "相关不等于因果" in trends.json()["data"]["disclaimer"]


async def test_export_csv_json_and_delete_confirmation(
    client: AsyncClient, auth_headers: dict[str, str], tmp_path: Path
) -> None:
    storage = LocalStorageProvider(tmp_path / "private")
    app.dependency_overrides[get_private_storage] = lambda: storage
    try:
        exported = await client.get("/api/v1/supervision/export/json", headers=auth_headers)
        assert exported.status_code == 200, exported.text
        assert exported.json()["format_version"] == "phase7-v1"
        assert "weights" in exported.json()["data"]
        csv_export = await client.get("/api/v1/supervision/export/csv", headers=auth_headers)
        assert csv_export.status_code == 200
        assert csv_export.text.startswith("category,date_or_time,name,value,unit,details")
        refused = await client.request(
            "DELETE",
            "/api/v1/supervision/data",
            headers=auth_headers,
            json={"confirmation": "delete"},
        )
        assert refused.status_code == 422
        deleted = await client.request(
            "DELETE",
            "/api/v1/supervision/data",
            headers=auth_headers,
            json={"confirmation": "DELETE MY DATA"},
        )
        assert deleted.status_code == 204, deleted.text
        after = await client.get("/api/v1/supervision/tasks", headers=auth_headers)
        assert after.status_code == 401
    finally:
        app.dependency_overrides.pop(get_private_storage, None)


async def test_report_service_cache_model_and_timeline_projection(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    del client, auth_headers
    user_id = await _user_id()
    async with SessionLocal() as session:
        service = HealthReportService(session, MockHealthAnswerProvider(), Settings())
        first = await service.generate(user_id, "daily", REFERENCE)
        second = await service.generate(user_id, "daily", REFERENCE)
        assert first.id == second.id
        events = await HealthTimelineService(session).list_events(
            user_id, REFERENCE, REFERENCE, "report"
        )
        assert events[0].event_type == "health_report"
        followups = list(
            (
                await session.scalars(
                    select(HealthFollowup).where(HealthFollowup.user_id == user_id)
                )
            ).all()
        )
        assert isinstance(followups, list)
