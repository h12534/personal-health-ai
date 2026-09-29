from datetime import timedelta

from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.security import create_token, hash_password
from app.db.session import SessionLocal
from app.models.food import FoodItem
from app.models.user import User
from app.scripts.seed_foods import seed_foods


async def _seed() -> int:
    async with SessionLocal() as session:
        inserted, _ = await seed_foods(session)
        return inserted


async def test_seed_is_idempotent_and_searches_alias(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    inserted = await _seed()
    assert inserted >= 40
    async with SessionLocal() as session:
        second_inserted, updated = await seed_foods(session)
        count = await session.scalar(select(func.count(FoodItem.id)))
    assert second_inserted == 0
    assert updated == inserted
    assert count == inserted

    result = await client.get("/api/v1/foods/search?q=西红柿", headers=auth_headers)
    assert result.status_code == 200
    assert result.json()["data"][0]["name"] == "番茄"


async def test_custom_food_crud_alias_favorite_and_soft_delete(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    payload = {
        "name": "学校一食堂黄焖鸡",
        "brand": "学校一食堂",
        "category": "mixed_dish",
        "serving_description": "1份约450g",
        "serving_unit": "serving",
        "serving_weight_g": 450,
        "calories_per_100g": 165,
        "protein_per_100g": 10.5,
        "carbs_per_100g": 12.0,
        "fat_per_100g": 8.0,
        "fiber_per_100g": 1.2,
        "aliases": ["一食堂黄焖鸡", "黄焖鸡套餐"],
    }
    created = await client.post("/api/v1/foods", headers=auth_headers, json=payload)
    assert created.status_code == 201
    food = created.json()["data"]
    assert food["is_custom"] is True
    assert food["source"] == "user"

    alias_search = await client.get("/api/v1/foods/search?q=黄焖鸡套餐", headers=auth_headers)
    assert alias_search.status_code == 200
    assert alias_search.json()["data"][0]["id"] == food["id"]

    favorite = await client.post(f"/api/v1/foods/{food['id']}/favorite", headers=auth_headers)
    assert favorite.status_code == 200
    assert favorite.json()["data"]["is_favorite"] is True
    favorites = await client.get("/api/v1/foods/favorites", headers=auth_headers)
    assert favorites.json()["data"][0]["food"]["id"] == food["id"]

    updated = await client.patch(
        f"/api/v1/foods/{food['id']}",
        headers=auth_headers,
        json={"calories_per_100g": 160, "aliases": ["校一黄焖鸡"]},
    )
    assert updated.status_code == 200
    assert float(updated.json()["data"]["calories_per_100g"]) == 160.0
    assert updated.json()["data"]["aliases"] == ["校一黄焖鸡"]

    deleted = await client.delete(f"/api/v1/foods/{food['id']}", headers=auth_headers)
    assert deleted.status_code == 204
    assert (
        await client.get(f"/api/v1/foods/{food['id']}", headers=auth_headers)
    ).status_code == 404


async def test_system_food_cannot_be_modified_and_custom_food_is_private(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    await _seed()
    rice = (await client.get("/api/v1/foods/search?q=米饭", headers=auth_headers)).json()["data"][0]
    assert (
        await client.patch(
            f"/api/v1/foods/{rice['id']}",
            headers=auth_headers,
            json={"calories_per_100g": 1},
        )
    ).status_code == 404

    custom = await client.post(
        "/api/v1/foods",
        headers=auth_headers,
        json={
            "name": "私有食物",
            "category": "other",
            "calories_per_100g": 100,
            "protein_per_100g": 10,
            "carbs_per_100g": 10,
            "fat_per_100g": 2,
            "fiber_per_100g": 1,
        },
    )
    custom_id = custom.json()["data"]["id"]
    async with SessionLocal() as session:
        other = User(
            email="other@example.com",
            password_hash=hash_password("another secure passphrase"),
        )
        session.add(other)
        await session.commit()
        await session.refresh(other)
        token, _ = create_token(other.id, "access", timedelta(minutes=5))
    other_headers = {"Authorization": f"Bearer {token}"}
    assert (
        await client.get(f"/api/v1/foods/{custom_id}", headers=other_headers)
    ).status_code == 404
    system_visible = await client.get(f"/api/v1/foods/{rice['id']}", headers=other_headers)
    assert system_visible.status_code == 200


async def test_food_validation_rejects_polluting_values(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    response = await client.post(
        "/api/v1/foods",
        headers=auth_headers,
        json={
            "name": "坏数据",
            "calories_per_100g": -1,
            "protein_per_100g": 0,
            "carbs_per_100g": 0,
            "fat_per_100g": 0,
        },
    )
    assert response.status_code == 422
    assert (await client.get("/api/v1/foods")).status_code == 401
