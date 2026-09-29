from datetime import date, datetime, timedelta
from uuid import UUID, uuid4

from httpx import AsyncClient
from sqlalchemy import select

from app.core.security import create_token, hash_password
from app.db.session import SessionLocal
from app.models.diet_coach import CoachMessage
from app.models.user import User


async def _second_user(client: AsyncClient) -> dict[str, str]:
    del client
    async with SessionLocal() as session:
        user = User(
            email=f"second-{uuid4().hex}@example.com",
            password_hash=hash_password("correct horse battery staple"),
            is_superuser=False,
        )
        session.add(user)
        await session.flush()
        token, _ = create_token(user.id, "access", timedelta(minutes=30))
        await session.commit()
    return {"Authorization": f"Bearer {token}"}


async def _goal(client: AsyncClient, headers: dict[str, str]) -> None:
    today = date.today()
    response = await client.post(
        "/api/v1/nutrition/goals",
        headers=headers,
        json={
            "effective_from": today.isoformat(),
            "calorie_target": 2200,
            "protein_target_g": 140,
            "carbs_target_g": 250,
            "fat_target_g": 70,
        },
    )
    assert response.status_code == 201


async def test_next_meal_canteen_recommendation_and_tenant_isolation(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    await _goal(client, auth_headers)
    plan = await client.get("/api/v1/diet/next-meal?hour=12", headers=auth_headers)
    assert plan.status_code == 200
    assert plan.json()["data"]["meal_type"] == "lunch"
    assert float(plan.json()["data"]["target"]["protein_min_g"]) > 0

    canteen = await client.post(
        "/api/v1/canteens",
        headers=auth_headers,
        json={"name": "第一食堂", "location": "东区"},
    )
    assert canteen.status_code == 201
    canteen_id = canteen.json()["data"]["id"]
    stall = await client.post(
        f"/api/v1/canteens/{canteen_id}/stalls",
        headers=auth_headers,
        json={"name": "家常菜", "cuisine": "中式"},
    )
    stall_id = stall.json()["data"]["id"]
    dish = await client.post(
        f"/api/v1/canteens/stalls/{stall_id}/dishes",
        headers=auth_headers,
        json={
            "name": "鸡胸肉套餐",
            "calories": 560,
            "protein_g": 42,
            "carbs_g": 65,
            "fat_g": 14,
            "fiber_g": 8,
            "tags": ["高蛋白"],
        },
    )
    assert dish.status_code == 201

    canteen_tree = await client.get("/api/v1/canteens", headers=auth_headers)
    assert canteen_tree.status_code == 200
    assert canteen_tree.json()["data"][0]["stalls"][0]["name"] == "家常菜"
    assert canteen_tree.json()["data"][0]["stalls"][0]["dishes"][0]["favorite"] is False

    recommended = await client.get(
        f"/api/v1/canteens/recommendations?canteen_id={canteen_id}", headers=auth_headers
    )
    assert recommended.status_code == 200
    assert recommended.json()["data"][0]["dish"]["name"] == "鸡胸肉套餐"
    combined = await client.get("/api/v1/diet/meal-recommendations", headers=auth_headers)
    assert combined.status_code == 200
    assert any(item["source"] == "canteen_dish" for item in combined.json()["data"])

    other_headers = await _second_user(client)
    forbidden_as_not_found = await client.delete(
        f"/api/v1/canteens/{canteen_id}", headers=other_headers
    )
    assert forbidden_as_not_found.status_code == 404


async def test_saved_meal_logging_is_idempotent(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    created = await client.post(
        "/api/v1/saved-meals",
        headers=auth_headers,
        json={
            "name": "宿舍早餐",
            "meal_type": "breakfast",
            "items": [
                {
                    "food_name": "牛奶燕麦",
                    "amount": 1,
                    "amount_unit": "serving",
                    "weight_g": 350,
                    "calories": 420,
                    "protein": 24,
                    "carbs": 55,
                    "fat": 12,
                    "fiber": 7,
                }
            ],
        },
    )
    assert created.status_code == 201
    assert created.json()["data"]["items"][0]["food_name"] == "牛奶燕麦"
    saved_id = created.json()["data"]["id"]
    payload = {
        "eaten_at": datetime.now().astimezone().isoformat(),
        "idempotency_key": "saved-meal-test-0001",
    }
    first = await client.post(
        f"/api/v1/saved-meals/{saved_id}/log", headers=auth_headers, json=payload
    )
    second = await client.post(
        f"/api/v1/saved-meals/{saved_id}/log", headers=auth_headers, json=payload
    )
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["data"]["id"] == second.json()["data"]["id"]


async def test_ai_coach_mock_and_safety_layer(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    meal = await client.post(
        "/api/v1/ai/coach/chat",
        headers=auth_headers,
        json={"message": "食堂午饭吃什么"},
    )
    assert meal.status_code == 200
    assert meal.json()["data"]["intent"] == "canteen_choice"
    assert meal.json()["data"]["provider"] == "mock"
    assert meal.json()["data"]["suggested_actions"][0]["type"] == "open_next_meal"
    assert (
        "profile" in meal.json()["data"]["used_context"]
        or "canteens" in meal.json()["data"]["used_context"]
    )
    assert meal.json()["data"]["references"] == []
    async with SessionLocal() as session:
        audited = await session.scalar(
            select(CoachMessage)
            .where(
                CoachMessage.conversation_id == UUID(meal.json()["data"]["conversation_id"]),
                CoachMessage.role == "assistant",
            )
            .order_by(CoachMessage.created_at.desc())
            .limit(1)
        )
        assert audited is not None and audited.structured_payload is not None
        assert len(str(audited.structured_payload["input_snapshot_hash"])) == 64
        assert audited.structured_payload["rule_version"] == "diet_rules_v1"
        assert audited.structured_payload["prompt_version"] == "diet_coach_v1"
        assert audited.structured_payload["model"] == "mock-coach-v1"

    emergency = await client.post(
        "/api/v1/ai/coach/chat",
        headers=auth_headers,
        json={"message": "我胸痛而且呼吸困难"},
    )
    assert emergency.status_code == 200
    data = emergency.json()["data"]
    assert data["provider"] == "safety_layer"
    assert data["intent"] == "emergency_health"
    assert "120" in data["message"]

    missing_other_conversation = await client.post(
        "/api/v1/ai/coach/chat",
        headers=await _second_user(client),
        json={
            "message": "继续",
            "conversation_id": meal.json()["data"]["conversation_id"],
        },
    )
    assert missing_other_conversation.status_code == 404


async def test_hunger_and_personal_memory_are_user_managed(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    hunger = await client.post(
        "/api/v1/diet/hunger",
        headers=auth_headers,
        json={
            "hunger_level": 4,
            "craving_level": 3,
            "context": "before_dinner",
            "note": "今天训练后比较饿",
        },
    )
    assert hunger.status_code == 201
    assert hunger.json()["data"]["hunger_level"] == 4

    memory = await client.post(
        "/api/v1/diet/memories",
        headers=auth_headers,
        json={"kind": "preference", "key": "staple", "value": "更喜欢米饭而不是面条"},
    )
    assert memory.status_code == 201
    memory_id = memory.json()["data"]["id"]
    assert memory.json()["data"]["source"] == "explicit_user_statement"
    assert memory.json()["data"]["last_confirmed_at"] is not None
    updated = await client.patch(
        f"/api/v1/diet/memories/{memory_id}",
        headers=auth_headers,
        json={"kind": "preference", "key": "staple", "value": "更喜欢米饭，也可以吃面"},
    )
    assert updated.status_code == 200
    assert updated.json()["data"]["value"] == "更喜欢米饭，也可以吃面"
    listed = await client.get("/api/v1/diet/memories", headers=auth_headers)
    assert listed.status_code == 200
    assert listed.json()["data"][0]["value"] == "更喜欢米饭，也可以吃面"
    deleted = await client.delete(f"/api/v1/diet/memories/{memory_id}", headers=auth_headers)
    assert deleted.status_code == 204
