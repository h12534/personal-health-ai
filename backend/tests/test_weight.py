from datetime import date, timedelta

from httpx import AsyncClient


async def test_weight_crud_trend_and_dashboard(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    today = date.today()
    ids: list[str] = []
    for offset in range(13, -1, -1):
        measured_on = today - timedelta(days=offset)
        weight = 101.3 - (13 - offset) * 0.1
        response = await client.post(
            "/api/v1/weight",
            headers=auth_headers,
            json={"measured_on": measured_on.isoformat(), "weight_kg": round(weight, 2)},
        )
        assert response.status_code == 201
        ids.append(response.json()["data"]["id"])

    duplicate = await client.post(
        "/api/v1/weight",
        headers=auth_headers,
        json={"measured_on": today.isoformat(), "weight_kg": 99.0},
    )
    assert duplicate.status_code == 409

    trend = await client.get("/api/v1/weight/trends?days=30", headers=auth_headers)
    assert trend.status_code == 200
    summary = trend.json()["data"]
    assert len(summary["points"]) == 14
    assert summary["latest_weight_kg"] == 100.0
    assert summary["week_change_kg"] == -0.7

    dashboard = await client.get("/api/v1/dashboard/today", headers=auth_headers)
    assert dashboard.status_code == 200
    assert dashboard.json()["data"]["morning_weight_completed"] is True
    assert dashboard.json()["data"]["today_weight_kg"] == 100.0

    updated = await client.patch(
        f"/api/v1/weight/{ids[-1]}", headers=auth_headers, json={"weight_kg": 99.9}
    )
    assert updated.status_code == 200
    assert updated.json()["data"]["weight_kg"] == "99.90"

    deleted = await client.delete(f"/api/v1/weight/{ids[0]}", headers=auth_headers)
    assert deleted.status_code == 204
    history = await client.get("/api/v1/weight", headers=auth_headers)
    assert len(history.json()["data"]) == 13

    restored = await client.post(
        "/api/v1/weight",
        headers=auth_headers,
        json={
            "measured_on": (today - timedelta(days=13)).isoformat(),
            "weight_kg": 101.2,
        },
    )
    assert restored.status_code == 201
    assert restored.json()["data"]["id"] == ids[0]


async def test_dashboard_prompts_for_missing_morning_weight(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    response = await client.get("/api/v1/dashboard/today", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["morning_weight_completed"] is False
    assert "晨重" in data["ai_next_action"]
