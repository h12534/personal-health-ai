import uuid

import pytest
from httpx import AsyncClient

from app.core.config import get_settings


async def test_provider_status_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/api/v1/profile/beta-status")
    assert response.status_code == 401


async def test_provider_status_is_allowlisted_and_not_a_live_test(
    client: AsyncClient,
    auth_headers: dict[str, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = get_settings()
    monkeypatch.setattr(settings, "coach_provider", "openai_compatible")
    monkeypatch.setattr(settings, "coach_api_key", "private-provider-test-value")
    monkeypatch.setattr(settings, "coach_base_url", "https://private-provider.test/token-sensitive")
    response = await client.get("/api/v1/profile/beta-status", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["data"] == {
        "coach": "configured_not_verified",
        "vision": "mock",
        "embedding": "mock",
        "lab_ocr": "mock",
        "health_answer": "mock",
        "push": "mock",
    }
    assert "private-provider" not in response.text
    assert "healthy" not in response.text


async def test_safe_request_id_is_preserved(client: AsyncClient) -> None:
    identifier = str(uuid.uuid4())
    response = await client.get("/health/live", headers={"X-Request-ID": identifier})
    assert response.headers["X-Request-ID"] == identifier


async def test_request_id_cannot_echo_secret_or_unstructured_text(client: AsyncClient) -> None:
    response = await client.get(
        "/health/live", headers={"X-Request-ID": "Bearer private-test-value"}
    )
    assert str(uuid.UUID(response.headers["X-Request-ID"])) == response.headers["X-Request-ID"]
    assert "private-test-value" not in response.headers["X-Request-ID"]
