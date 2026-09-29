from httpx import AsyncClient


async def test_register_login_refresh_and_me(client: AsyncClient) -> None:
    register = await client.post(
        "/api/v1/auth/register",
        json={"email": "Owner@Example.com", "password": "correct horse battery staple"},
    )
    assert register.status_code == 201
    pair = register.json()["data"]

    me = await client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {pair['access_token']}"},
    )
    assert me.status_code == 200
    assert me.json()["data"]["email"] == "owner@example.com"

    refresh = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]}
    )
    assert refresh.status_code == 200
    rotated = refresh.json()["data"]
    assert rotated["refresh_token"] != pair["refresh_token"]

    replay = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]}
    )
    assert replay.status_code == 401
    assert replay.json()["error"]["code"] == "invalid_refresh_token"


async def test_private_instance_allows_only_one_registration(client: AsyncClient) -> None:
    payload = {"email": "owner@example.com", "password": "correct horse battery staple"}
    assert (await client.post("/api/v1/auth/register", json=payload)).status_code == 201
    second = await client.post(
        "/api/v1/auth/register",
        json={"email": "other@example.com", "password": "another secure passphrase"},
    )
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "registration_closed"


async def test_bad_password_and_missing_auth_are_rejected(client: AsyncClient) -> None:
    await client.post(
        "/api/v1/auth/register",
        json={"email": "owner@example.com", "password": "correct horse battery staple"},
    )
    bad_login = await client.post(
        "/api/v1/auth/login", json={"email": "owner@example.com", "password": "wrong"}
    )
    assert bad_login.status_code == 401
    assert (await client.get("/api/v1/auth/me")).status_code == 401
