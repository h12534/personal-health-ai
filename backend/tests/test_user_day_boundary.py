from datetime import UTC, date, datetime, timedelta, tzinfo

import pytest
from httpx import AsyncClient

from app.api.v1.endpoints import weight
from app.services import daily_nutrition_service


@pytest.mark.parametrize(
    ("timezone", "instant", "expected_day"),
    [
        ("Asia/Shanghai", datetime(2026, 10, 3, 16, 30, tzinfo=UTC), date(2026, 10, 4)),
        ("America/Los_Angeles", datetime(2026, 10, 4, 1, 30, tzinfo=UTC), date(2026, 10, 3)),
    ],
)
async def test_weight_trend_and_dashboard_agree_on_user_day_not_host_day(
    client: AsyncClient,
    auth_headers: dict[str, str],
    monkeypatch: pytest.MonkeyPatch,
    timezone: str,
    instant: datetime,
    expected_day: date,
) -> None:
    class FrozenClock(datetime):
        @classmethod
        def now(cls, tz: tzinfo | None = None) -> datetime:
            return instant.astimezone(tz) if tz is not None else instant.replace(tzinfo=None)

    class HostUTCDate(date):
        @classmethod
        def today(cls) -> date:
            return instant.date()

    assert expected_day != instant.date()  # Explicit opposite-date boundary, not a noon shortcut.
    monkeypatch.setattr(weight, "datetime", FrozenClock)
    monkeypatch.setattr(weight, "date", HostUTCDate)
    monkeypatch.setattr(daily_nutrition_service, "datetime", FrozenClock)
    response = await client.put(
        "/api/v1/profile", headers=auth_headers, json={"timezone": timezone}
    )
    assert response.status_code == 200
    for offset, value in ((-1, 80), (0, 81), (1, 82)):
        response = await client.post(
            "/api/v1/weight",
            headers=auth_headers,
            json={
                "measured_on": (expected_day + timedelta(days=offset)).isoformat(),
                "weight_kg": value,
            },
        )
        assert response.status_code == 201
    trend = await client.get("/api/v1/weight/trends?days=7", headers=auth_headers)
    assert trend.status_code == 200
    data = trend.json()["data"]
    assert len(data["points"]) == 2
    assert data["points"][-1]["measured_on"] == expected_day.isoformat()
    assert data["latest_weight_kg"] == 81
    dashboard = await client.get("/api/v1/dashboard/today", headers=auth_headers)
    assert dashboard.status_code == 200
    assert dashboard.json()["data"]["date"] == expected_day.isoformat()
    assert dashboard.json()["data"]["today_weight_kg"] == 81
