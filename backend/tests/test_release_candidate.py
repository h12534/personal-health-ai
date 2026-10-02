from datetime import UTC, date, datetime, time
from decimal import Decimal
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.db.session import SessionLocal
from app.models.supervision import PushDevice
from app.models.user import User
from app.models.weight_log import WeightLog
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.reminder_service import ReminderEngine


async def _user_id() -> UUID:
    async with SessionLocal() as session:
        value = await session.scalar(select(User.id).where(User.email == "owner@example.com"))
        assert value is not None
        return value


async def test_push_device_environment_and_token_rotation(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    first = await client.put(
        "/api/v1/supervision/push-device",
        headers=auth_headers,
        json={
            "device_id": "owner-iphone",
            "platform": "ios",
            "environment": "staging",
            "token": "staging-token-0001",
        },
    )
    assert first.status_code == 200, first.text
    assert first.json()["data"]["environment"] == "staging"

    rotated = await client.put(
        "/api/v1/supervision/push-device",
        headers=auth_headers,
        json={
            "device_id": "owner-iphone",
            "platform": "ios",
            "environment": "prod",
            "token": "production-token-0002",
        },
    )
    assert rotated.status_code == 200, rotated.text
    assert rotated.json()["data"]["id"] == first.json()["data"]["id"]
    assert rotated.json()["data"]["environment"] == "prod"

    async with SessionLocal() as session:
        devices = list((await session.scalars(select(PushDevice))).all())
        assert len(devices) == 1
        assert devices[0].token == "production-token-0002"
        assert devices[0].environment == "prod"
        assert devices[0].active is True


async def test_timeline_has_bounded_pagination(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    user_id = await _user_id()
    async with SessionLocal() as session:
        for day in range(1, 6):
            session.add(
                WeightLog(
                    user_id=user_id,
                    measured_on=date(2026, 10, day),
                    weight_kg=Decimal(f"{100 - day}.0"),
                    source="rc-test",
                )
            )
        await session.commit()

    first = await client.get(
        "/api/v1/supervision/timeline",
        headers=auth_headers,
        params={
            "from": "2026-10-01",
            "to": "2026-10-05",
            "category": "body",
            "limit": 2,
            "offset": 0,
        },
    )
    second = await client.get(
        "/api/v1/supervision/timeline",
        headers=auth_headers,
        params={
            "from": "2026-10-01",
            "to": "2026-10-05",
            "category": "body",
            "limit": 2,
            "offset": 2,
        },
    )
    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["meta"] == {"count": 2, "limit": 2, "offset": 0}
    assert second.json()["meta"] == {"count": 2, "limit": 2, "offset": 2}
    assert {item["id"] for item in first.json()["data"]}.isdisjoint(
        {item["id"] for item in second.json()["data"]}
    )

    rejected = await client.get(
        "/api/v1/supervision/timeline",
        headers=auth_headers,
        params={"from": "2026-10-01", "to": "2026-10-05", "limit": 501},
    )
    assert rejected.status_code == 422


@pytest.mark.parametrize(
    ("timezone_name", "expected_start"),
    [
        ("UTC", datetime(2026, 10, 1, 0, 0, tzinfo=UTC)),
        ("Asia/Tokyo", datetime(2026, 9, 30, 15, 0, tzinfo=UTC)),
        ("Asia/Shanghai", datetime(2026, 9, 30, 16, 0, tzinfo=UTC)),
    ],
)
def test_profile_timezone_day_boundaries(timezone_name: str, expected_start: datetime) -> None:
    start, end = DailyNutritionService._utc_bounds(
        date(2026, 10, 1), date(2026, 10, 1), ZoneInfo(timezone_name)
    )
    assert start == expected_start
    assert (end - start).total_seconds() == 24 * 60 * 60


def test_dst_and_overnight_dnd_boundaries() -> None:
    start, end = DailyNutritionService._utc_bounds(
        date(2026, 3, 8), date(2026, 3, 8), ZoneInfo("America/New_York")
    )
    assert (end - start).total_seconds() == 23 * 60 * 60
    assert ReminderEngine._inside_dnd(time(23, 59), time(23), time(7, 30)) is True
    assert ReminderEngine._inside_dnd(time(0, 0), time(23), time(7, 30)) is True
    assert ReminderEngine._inside_dnd(time(7, 30), time(23), time(7, 30)) is False


async def test_push_device_environment_validation(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    response = await client.put(
        "/api/v1/supervision/push-device",
        headers=auth_headers,
        json={
            "device_id": "owner-iphone",
            "platform": "ios",
            "environment": "unknown",
            "token": "staging-token-0001",
        },
    )
    assert response.status_code == 422
    async with SessionLocal() as session:
        assert await session.scalar(select(func.count(PushDevice.id))) == 0
