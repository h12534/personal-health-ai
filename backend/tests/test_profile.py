from httpx import AsyncClient


async def test_profile_upsert_and_read(client: AsyncClient, auth_headers: dict[str, str]) -> None:
    missing = await client.get("/api/v1/profile", headers=auth_headers)
    assert missing.status_code == 404

    payload = {
        "birth_date": "2005-01-01",
        "sex": "male",
        "height_cm": "176.0",
        "target_weight_kg": "80.0",
        "primary_goal": "fat_loss_muscle_retention",
        "school_life": True,
        "dietary_environment": ["school_canteen", "takeout", "convenience_store"],
        "available_equipment": ["school_gym"],
        "timezone": "Asia/Shanghai",
    }
    created = await client.put("/api/v1/profile", headers=auth_headers, json=payload)
    assert created.status_code == 200
    assert float(created.json()["data"]["height_cm"]) == 176.0
    assert created.json()["data"]["school_life"] is True

    fetched = await client.get("/api/v1/profile", headers=auth_headers)
    assert fetched.status_code == 200
    assert fetched.json()["data"]["dietary_environment"][0] == "school_canteen"


async def test_profile_validates_physical_ranges(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    response = await client.put("/api/v1/profile", headers=auth_headers, json={"height_cm": 400})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
