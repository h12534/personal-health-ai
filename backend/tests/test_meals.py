from datetime import date, timedelta

from httpx import AsyncClient

from app.db.session import SessionLocal
from app.scripts.seed_foods import seed_foods


async def _food_id(client: AsyncClient, headers: dict[str, str], query: str) -> str:
    result = await client.get(f"/api/v1/foods/search?q={query}", headers=headers)
    assert result.status_code == 200
    return result.json()["data"][0]["id"]


async def test_meal_item_crud_snapshots_totals_recent_and_idempotency(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    async with SessionLocal() as session:
        await seed_foods(session)
    rice_id = await _food_id(client, auth_headers, "米饭")
    egg_id = await _food_id(client, auth_headers, "鸡蛋")
    today = date.today()
    meal_payload = {
        "meal_type": "breakfast",
        "eaten_at": f"{today.isoformat()}T08:00:00+08:00",
        "note": "晨练后",
    }
    first = await client.post(
        "/api/v1/meals",
        headers={**auth_headers, "Idempotency-Key": "meal-local-001"},
        json=meal_payload,
    )
    replay = await client.post(
        "/api/v1/meals",
        headers={**auth_headers, "Idempotency-Key": "meal-local-001"},
        json=meal_payload,
    )
    assert first.status_code == replay.status_code == 201
    meal_id = first.json()["data"]["id"]
    assert replay.json()["data"]["id"] == meal_id

    rice = await client.post(
        f"/api/v1/meals/{meal_id}/items",
        headers={**auth_headers, "Idempotency-Key": "item-local-rice"},
        json={"food_id": rice_id, "amount": 200, "amount_unit": "g"},
    )
    assert rice.status_code == 200
    data = rice.json()["data"]
    assert float(data["total_calories"]) == 260.0
    assert float(data["total_protein"]) == 5.4
    assert data["items"][0]["food_name_snapshot"] == "米饭"
    rice_item_id = data["items"][0]["id"]

    item_replay = await client.post(
        f"/api/v1/meals/{meal_id}/items",
        headers={**auth_headers, "Idempotency-Key": "item-local-rice"},
        json={"food_id": rice_id, "amount": 200, "amount_unit": "g"},
    )
    assert len(item_replay.json()["data"]["items"]) == 1

    eggs = await client.post(
        f"/api/v1/meals/{meal_id}/items",
        headers={**auth_headers, "Idempotency-Key": "item-local-eggs"},
        json={"food_id": egg_id, "amount": 2, "amount_unit": "piece"},
    )
    meal = eggs.json()["data"]
    assert float(meal["total_calories"]) == 403.0
    egg_item_id = next(item["id"] for item in meal["items"] if item["food_id"] == egg_id)

    updated = await client.patch(
        f"/api/v1/meals/{meal_id}/items/{rice_item_id}",
        headers=auth_headers,
        json={"amount": 150},
    )
    assert float(updated.json()["data"]["total_calories"]) == 338.0

    after_delete = await client.delete(
        f"/api/v1/meals/{meal_id}/items/{egg_item_id}", headers=auth_headers
    )
    assert float(after_delete.json()["data"]["total_calories"]) == 195.0
    assert len(after_delete.json()["data"]["items"]) == 1

    listed = await client.get(
        f"/api/v1/meals?from={today.isoformat()}&to={today.isoformat()}", headers=auth_headers
    )
    assert len(listed.json()["data"]) == 1
    recent = await client.get("/api/v1/foods/recent", headers=auth_headers)
    assert recent.json()["data"][0]["id"] == rice_id

    assert (
        await client.delete(f"/api/v1/meals/{meal_id}", headers=auth_headers)
    ).status_code == 204
    assert (await client.get(f"/api/v1/meals/{meal_id}", headers=auth_headers)).status_code == 404


async def test_meal_requires_timezone_and_filters_by_user_local_date(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    today = date.today()
    naive = await client.post(
        "/api/v1/meals",
        headers=auth_headers,
        json={"meal_type": "snack", "eaten_at": f"{today.isoformat()}T08:00:00"},
    )
    assert naive.status_code == 422

    aware = await client.post(
        "/api/v1/meals",
        headers=auth_headers,
        json={"meal_type": "snack", "eaten_at": f"{today.isoformat()}T00:30:00+08:00"},
    )
    assert aware.status_code == 201
    assert aware.json()["data"]["eaten_at"].endswith("Z")
    local_day = await client.get(
        f"/api/v1/meals?from={today.isoformat()}&to={today.isoformat()}", headers=auth_headers
    )
    assert len(local_day.json()["data"]) == 1
    previous = today - timedelta(days=1)
    previous_day = await client.get(
        f"/api/v1/meals?from={previous.isoformat()}&to={previous.isoformat()}",
        headers=auth_headers,
    )
    assert previous_day.json()["data"] == []


async def test_meal_ownership_is_enforced(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    created = await client.post(
        "/api/v1/meals",
        headers=auth_headers,
        json={"meal_type": "lunch", "eaten_at": "2026-09-29T12:00:00+08:00"},
    )
    meal_id = created.json()["data"]["id"]
    assert (await client.get(f"/api/v1/meals/{meal_id}")).status_code == 401
