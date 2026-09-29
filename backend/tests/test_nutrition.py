from datetime import date, timedelta

from httpx import AsyncClient

from app.db.session import SessionLocal
from app.scripts.seed_foods import seed_foods


async def _food_id(client: AsyncClient, headers: dict[str, str], query: str) -> str:
    response = await client.get(f"/api/v1/foods/search?q={query}", headers=headers)
    assert response.status_code == 200
    return response.json()["data"][0]["id"]


async def _add_food(
    client: AsyncClient,
    headers: dict[str, str],
    meal_id: str,
    food_id: str,
    amount: int,
    unit: str,
) -> None:
    response = await client.post(
        f"/api/v1/meals/{meal_id}/items",
        headers=headers,
        json={"food_id": food_id, "amount": amount, "amount_unit": unit},
    )
    assert response.status_code == 200


async def test_daily_range_goals_and_dashboard_use_real_meal_totals(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    async with SessionLocal() as session:
        await seed_foods(session)
    rice_id = await _food_id(client, auth_headers, "米饭")
    egg_id = await _food_id(client, auth_headers, "鸡蛋")
    today = date.today()

    breakfast = await client.post(
        "/api/v1/meals",
        headers=auth_headers,
        json={"meal_type": "breakfast", "eaten_at": f"{today}T08:00:00+08:00"},
    )
    assert breakfast.status_code == 201
    meal_id = breakfast.json()["data"]["id"]
    await _add_food(client, auth_headers, meal_id, rice_id, 200, "g")
    await _add_food(client, auth_headers, meal_id, egg_id, 2, "piece")

    goal_payload = {
        "effective_from": today.isoformat(),
        "calorie_target": 2200,
        "protein_target_g": 135,
        "carbs_target_g": 250,
        "fat_target_g": 70,
        "fiber_target_g": 25,
        "water_target_ml": 2500,
        "source": "manual",
    }
    created_goal = await client.post(
        "/api/v1/nutrition/goals", headers=auth_headers, json=goal_payload
    )
    assert created_goal.status_code == 201
    goal_id = created_goal.json()["data"]["id"]

    daily = await client.get(f"/api/v1/nutrition/daily?date={today}", headers=auth_headers)
    assert daily.status_code == 200
    nutrition = daily.json()["data"]
    assert float(nutrition["totals"]["calories"]) == 403.0
    assert float(nutrition["totals"]["protein"]) == 18.0
    assert float(nutrition["meals"]["breakfast"]["calories"]) == 403.0
    assert nutrition["meal_counts"]["breakfast"] == 1
    assert nutrition["meal_counts"]["lunch"] == 0

    date_from = today - timedelta(days=1)
    ranged = await client.get(
        f"/api/v1/nutrition/range?from={date_from}&to={today}", headers=auth_headers
    )
    assert ranged.status_code == 200
    days = ranged.json()["data"]
    assert len(days) == 2
    assert float(days[0]["totals"]["calories"]) == 0
    assert float(days[1]["totals"]["calories"]) == 403.0

    current = await client.get(
        f"/api/v1/nutrition/goals/current?date={today}", headers=auth_headers
    )
    assert current.status_code == 200
    assert current.json()["data"]["calorie_target"] == 2200

    updated = await client.patch(
        f"/api/v1/nutrition/goals/{goal_id}",
        headers=auth_headers,
        json={"protein_target_g": 140},
    )
    assert updated.status_code == 200
    assert float(updated.json()["data"]["protein_target_g"]) == 140

    weight = await client.post(
        "/api/v1/weight",
        headers=auth_headers,
        json={"measured_on": today.isoformat(), "weight_kg": 100},
    )
    assert weight.status_code == 201
    dashboard = await client.get("/api/v1/dashboard/today", headers=auth_headers)
    assert dashboard.status_code == 200
    dashboard_data = dashboard.json()["data"]
    assert dashboard_data["calories_consumed"] == 403
    assert dashboard_data["calories_target"] == 2200
    assert dashboard_data["protein_g"] == 18.0
    assert dashboard_data["protein_target_g"] == 140.0
    assert dashboard_data["breakfast_logged"] is True
    assert dashboard_data["lunch_logged"] is False


async def test_goal_history_validation_suggestion_and_ownership(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    today = date.today()
    too_low = await client.post(
        "/api/v1/nutrition/goals",
        headers=auth_headers,
        json={
            "effective_from": today.isoformat(),
            "calorie_target": 1000,
            "protein_target_g": 120,
        },
    )
    assert too_low.status_code == 422

    first = await client.post(
        "/api/v1/nutrition/goals",
        headers=auth_headers,
        json={
            "effective_from": today.isoformat(),
            "calorie_target": 2200,
            "protein_target_g": 135,
        },
    )
    assert first.status_code == 201
    tomorrow = today + timedelta(days=1)
    second = await client.post(
        "/api/v1/nutrition/goals",
        headers=auth_headers,
        json={
            "effective_from": tomorrow.isoformat(),
            "calorie_target": 2100,
            "protein_target_g": 140,
        },
    )
    assert second.status_code == 201
    duplicate = await client.post(
        "/api/v1/nutrition/goals",
        headers=auth_headers,
        json={
            "effective_from": tomorrow.isoformat(),
            "calorie_target": 2050,
            "protein_target_g": 145,
        },
    )
    assert duplicate.status_code == 409
    yesterday = today - timedelta(days=1)
    historical = await client.post(
        "/api/v1/nutrition/goals",
        headers=auth_headers,
        json={
            "effective_from": yesterday.isoformat(),
            "calorie_target": 2300,
            "protein_target_g": 130,
        },
    )
    assert historical.status_code == 201
    today_goal = await client.get(
        f"/api/v1/nutrition/goals/current?date={today}", headers=auth_headers
    )
    tomorrow_goal = await client.get(
        f"/api/v1/nutrition/goals/current?date={tomorrow}", headers=auth_headers
    )
    assert today_goal.json()["data"]["id"] == first.json()["data"]["id"]
    assert tomorrow_goal.json()["data"]["id"] == second.json()["data"]["id"]
    historical_goal = await client.get(
        f"/api/v1/nutrition/goals/current?date={yesterday}", headers=auth_headers
    )
    assert historical_goal.json()["data"]["id"] == historical.json()["data"]["id"]

    suggested = await client.get("/api/v1/nutrition/goals/suggested", headers=auth_headers)
    assert suggested.status_code == 200
    suggestion = suggested.json()["data"]
    assert suggestion["calorie_target"] >= 1400
    assert suggestion["source"] == "program_suggestion"

    assert (await client.get("/api/v1/nutrition/daily")).status_code == 401
    assert (
        await client.patch(
            f"/api/v1/nutrition/goals/{first.json()['data']['id']}",
            json={"protein_target_g": 150},
        )
    ).status_code == 401
