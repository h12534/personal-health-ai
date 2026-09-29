import json
from datetime import UTC, date, datetime, timedelta
from io import BytesIO
from pathlib import Path
from uuid import UUID

import pytest
from httpx import AsyncClient
from PIL import Image
from sqlalchemy import func, select

from app.api.dependencies import get_private_storage, get_vision_provider
from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.core.security import create_token
from app.db.session import SessionLocal
from app.main import app
from app.models.meal_analysis import (
    AIUsageLog,
    MealAnalysisSession,
    MealImage,
    PersonalFoodMemory,
)
from app.models.user import User
from app.providers.ai.mock_vision import MockVisionProvider
from app.providers.storage.local import LocalStorageProvider
from app.scripts.seed_foods import seed_foods
from app.services.meal_analysis_service import MealAnalysisService

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "meal_vision"


def _fixture(name: str) -> dict[str, object]:
    return json.loads((FIXTURE_DIR / name).read_text(encoding="utf-8"))


def _image_bytes(image_format: str = "PNG") -> bytes:
    output = BytesIO()
    Image.new("RGB", (320, 240), (210, 170, 90)).save(output, format=image_format)
    return output.getvalue()


def _configure(tmp_path: Path, provider: MockVisionProvider | None = None) -> None:
    storage = LocalStorageProvider(tmp_path / "private")
    app.dependency_overrides[get_private_storage] = lambda: storage
    if provider is not None:
        app.dependency_overrides[get_vision_provider] = lambda: provider


async def _seed() -> None:
    async with SessionLocal() as session:
        await seed_foods(session)


async def _upload(
    client: AsyncClient,
    headers: dict[str, str],
    key: str,
    content: bytes | None = None,
    content_type: str = "image/png",
) -> object:
    return await client.post(
        "/api/v1/meals/analyze-image",
        headers={**headers, "Idempotency-Key": key},
        files={"image": ("ignored-client-name.png", content or _image_bytes(), content_type)},
        data={
            "location_context": "school_canteen",
            "meal_type": "lunch",
            "note": "学校食堂午餐",
        },
    )


@pytest.fixture(autouse=True)
def clear_dependency_overrides():  # type: ignore[no-untyped-def]
    yield
    app.dependency_overrides.clear()


async def test_analysis_happy_path_confirm_is_atomic_idempotent_and_learns(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    await _seed()
    _configure(
        tmp_path,
        MockVisionProvider(_fixture("meal_rice_egg_vegetable.json")),
    )
    response = await _upload(client, auth_headers, "analysis-happy-1")
    assert response.status_code == 202
    analysis = response.json()["data"]
    assert analysis["status"] == "completed"
    assert analysis["note"] == "学校食堂午餐"
    assert len(analysis["items"]) == 4
    assert any(item["is_hidden_ingredient"] for item in analysis["items"])
    assert float(analysis["totals"]["min_calories"]) < float(analysis["totals"]["max_calories"])
    rice = next(item for item in analysis["items"] if item["matched_food_name"] == "米饭")
    patched = await client.patch(
        f"/api/v1/meals/analyses/{analysis['id']}/items/{rice['id']}",
        headers=auth_headers,
        json={"estimated_weight_g": 200},
    )
    assert patched.status_code == 200
    assert (
        float(
            next(item for item in patched.json()["data"]["items"] if item["id"] == rice["id"])[
                "calories"
            ]
        )
        == 260.0
    )

    confirm_payload = {
        "meal_type": "lunch",
        "eaten_at": f"{date.today().isoformat()}T12:00:00+08:00",
        "note": "AI 草稿已人工确认",
    }
    confirmed = await client.post(
        f"/api/v1/meals/analyses/{analysis['id']}/confirm",
        headers={**auth_headers, "Idempotency-Key": "confirm-happy-1"},
        json=confirm_payload,
    )
    replay = await client.post(
        f"/api/v1/meals/analyses/{analysis['id']}/confirm",
        headers={**auth_headers, "Idempotency-Key": "confirm-replay"},
        json=confirm_payload,
    )
    assert confirmed.status_code == replay.status_code == 201
    meal = confirmed.json()["data"]
    assert meal["id"] == replay.json()["data"]["id"]
    assert meal["source"] == "vision_confirmed"
    assert len(meal["items"]) == 4
    assert all(item["nutrition_source"].startswith("vision_confirmed:") for item in meal["items"])
    dashboard = await client.get("/api/v1/dashboard/today", headers=auth_headers)
    assert dashboard.status_code == 200
    assert dashboard.json()["data"]["calories_consumed"] > 0

    async with SessionLocal() as session:
        memory_count = await session.scalar(select(func.count(PersonalFoodMemory.id)))
        usage_count = await session.scalar(select(func.count(AIUsageLog.id)))
        assert memory_count == 4
        assert usage_count == 1

    learned = await _upload(client, auth_headers, "analysis-happy-2")
    learned_types = {item["match_type"] for item in learned.json()["data"]["items"]}
    assert "personal_memory" in learned_types


async def test_analysis_upload_idempotency_draft_crud_and_ownership(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    await _seed()
    _configure(tmp_path, MockVisionProvider(_fixture("meal_multi_dish.json")))
    first = await _upload(client, auth_headers, "same-upload")
    second = await _upload(client, auth_headers, "same-upload")
    assert first.json()["data"]["id"] == second.json()["data"]["id"]
    analysis = first.json()["data"]
    hidden = next(item for item in analysis["items"] if item["is_hidden_ingredient"])
    deleted = await client.delete(
        f"/api/v1/meals/analyses/{analysis['id']}/items/{hidden['id']}",
        headers=auth_headers,
    )
    assert len(deleted.json()["data"]["items"]) == len(analysis["items"]) - 1

    egg_search = await client.get("/api/v1/foods/search?q=鸡蛋", headers=auth_headers)
    egg_id = egg_search.json()["data"][0]["id"]
    added = await client.post(
        f"/api/v1/meals/analyses/{analysis['id']}/items",
        headers=auth_headers,
        json={"food_id": egg_id, "estimated_weight_g": 55, "detected_name": "加餐鸡蛋"},
    )
    assert any(item["detected_name"] == "加餐鸡蛋" for item in added.json()["data"]["items"])

    async with SessionLocal() as session:
        other = User(email="phase3-other@example.net", password_hash="unused-in-test")
        session.add(other)
        await session.commit()
        await session.refresh(other)
    token, _ = create_token(other.id, "access", timedelta(minutes=5))
    other_headers = {"Authorization": f"Bearer {token}"}
    forbidden = await client.get(f"/api/v1/meals/analyses/{analysis['id']}", headers=other_headers)
    assert forbidden.status_code == 404


async def test_no_food_invalid_provider_result_and_timeout_become_safe_failed_drafts(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    await _seed()
    cases = [
        (
            MockVisionProvider(_fixture("no_food.json")),
            "no-food",
            "no_food_detected",
        ),
        (
            MockVisionProvider(_fixture("invalid_json.json")),
            "invalid-result",
            "invalid_vision_response",
        ),
        (
            MockVisionProvider(error=AppError("vision_timeout", "Timed out.", 504)),
            "timeout",
            "vision_timeout",
        ),
        (
            MockVisionProvider(error=RuntimeError("synthetic provider failure")),
            "provider-failure",
            "vision_processing_failed",
        ),
    ]
    for provider, key, expected_code in cases:
        _configure(tmp_path / key, provider)
        response = await _upload(client, auth_headers, key)
        assert response.status_code == 202
        data = response.json()["data"]
        assert data["status"] == "failed"
        assert data["error_code"] == expected_code
        assert data["confirmed_meal_id"] is None


async def test_upload_rejects_spoofed_content_type_and_non_image(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    _configure(tmp_path)
    spoofed = await _upload(
        client,
        auth_headers,
        "spoofed",
        content=_image_bytes("PNG"),
        content_type="image/jpeg",
    )
    assert spoofed.status_code == 415
    assert spoofed.json()["error"]["code"] == "invalid_image_type"
    text = await _upload(
        client,
        auth_headers,
        "text-file",
        content=b"this is not an image",
        content_type="image/png",
    )
    assert text.status_code == 415


async def test_remote_provider_requires_explicit_profile_consent(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    class RemoteMock(MockVisionProvider):
        name = "remote_mock"
        model = "remote-test"
        is_remote = True

    await _seed()
    _configure(tmp_path, RemoteMock(_fixture("meal_multi_dish.json")))
    denied = await _upload(client, auth_headers, "remote-denied")
    assert denied.status_code == 403
    assert denied.json()["error"]["code"] == "third_party_vision_consent_required"
    profile = await client.put(
        "/api/v1/profile",
        headers=auth_headers,
        json={"allow_third_party_vision": True},
    )
    assert profile.status_code == 200
    allowed = await _upload(client, auth_headers, "remote-allowed")
    assert allowed.status_code == 202
    assert allowed.json()["data"]["provider"] == "remote_mock"


async def test_reanalysis_replaces_draft_and_can_be_deleted(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    await _seed()
    provider = MockVisionProvider(_fixture("meal_multi_dish.json"))
    _configure(tmp_path, provider)
    created = await _upload(client, auth_headers, "reanalyze")
    analysis_id = created.json()["data"]["id"]
    provider.payload = _fixture("meal_low_confidence.json")
    reanalyzed = await client.post(
        f"/api/v1/meals/analyses/{analysis_id}/reanalyze", headers=auth_headers
    )
    assert reanalyzed.status_code == 202
    assert reanalyzed.json()["data"]["reanalysis_count"] == 1
    assert reanalyzed.json()["data"]["confidence_label"] == "low"
    deleted = await client.delete(f"/api/v1/meals/analyses/{analysis_id}", headers=auth_headers)
    assert deleted.status_code == 204
    assert (
        await client.get(f"/api/v1/meals/analyses/{analysis_id}", headers=auth_headers)
    ).status_code == 404


async def test_analysis_rows_never_write_meal_before_confirmation(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    await _seed()
    _configure(tmp_path, MockVisionProvider(_fixture("meal_multi_dish.json")))
    created = await _upload(client, auth_headers, "draft-only")
    analysis_id = created.json()["data"]["id"]
    meals = await client.get(
        f"/api/v1/meals?from={date.today().isoformat()}&to={date.today().isoformat()}",
        headers=auth_headers,
    )
    assert meals.json()["data"] == []
    async with SessionLocal() as session:
        record = await session.scalar(
            select(MealAnalysisSession).where(MealAnalysisSession.id == UUID(analysis_id))
        )
        assert record is not None
        assert record.status == "completed"
        assert record.confirmed_meal_id is None


async def test_alias_match_and_unmatched_confirm_rolls_back_entire_meal(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    await _seed()
    alias_payload = _fixture("meal_rice_egg_vegetable.json")
    foods = alias_payload["foods"]
    assert isinstance(foods, list)
    alias_food = foods[0]
    assert isinstance(alias_food, dict)
    alias_food["detected_name"] = "白米饭"
    alias_food["aliases"] = []
    alias_payload["foods"] = [alias_food]
    _configure(tmp_path / "alias", MockVisionProvider(alias_payload))
    alias_result = await _upload(client, auth_headers, "alias-match")
    assert alias_result.json()["data"]["items"][0]["match_type"] == "alias"

    _configure(
        tmp_path / "unmatched",
        MockVisionProvider(_fixture("meal_low_confidence.json")),
    )
    unmatched = await _upload(client, auth_headers, "unmatched-rollback")
    analysis = unmatched.json()["data"]
    assert analysis["items"][0]["match_type"] == "unmatched"
    failed_confirm = await client.post(
        f"/api/v1/meals/analyses/{analysis['id']}/confirm",
        headers=auth_headers,
        json={
            "meal_type": "lunch",
            "eaten_at": f"{date.today().isoformat()}T12:00:00+08:00",
        },
    )
    assert failed_confirm.status_code == 422
    meals = await client.get(
        f"/api/v1/meals?from={date.today().isoformat()}&to={date.today().isoformat()}",
        headers=auth_headers,
    )
    assert meals.json()["data"] == []


async def test_retention_cleanup_expires_draft_raw_response_and_private_image(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    await _seed()
    storage = LocalStorageProvider(tmp_path / "private")
    app.dependency_overrides[get_private_storage] = lambda: storage
    app.dependency_overrides[get_vision_provider] = lambda: MockVisionProvider(
        _fixture("meal_multi_dish.json")
    )
    created = await _upload(client, auth_headers, "cleanup-expired")
    analysis_id = UUID(created.json()["data"]["id"])
    async with SessionLocal() as session:
        analysis = await session.get(MealAnalysisSession, analysis_id)
        assert analysis is not None
        image = await session.get(MealImage, analysis.image_id)
        assert image is not None
        object_path = storage.root / Path(*image.object_key.split("/"))
        assert object_path.exists()
        analysis.expires_at = datetime.now(UTC) - timedelta(hours=1)
        image.retention_expires_at = datetime.now(UTC) - timedelta(hours=1)
        await session.commit()
        service = MealAnalysisService(
            session,
            Settings(
                upload_dir=str(storage.root),
                vision_raw_response_retention_days=0,
            ),
            MockVisionProvider(),
            storage,
        )
        images_deleted, _ = await service.cleanup_expired()
        assert images_deleted == 1
        await session.refresh(analysis)
        assert analysis.status == "expired"
        assert analysis.raw_provider_response is None
        assert not object_path.exists()


async def test_zero_day_retention_keeps_draft_then_deletes_image_after_confirm(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    await _seed()
    storage = LocalStorageProvider(tmp_path / "private")
    settings = Settings(
        upload_dir=str(storage.root),
        meal_image_retention_days=0,
    )
    app.dependency_overrides[get_private_storage] = lambda: storage
    app.dependency_overrides[get_vision_provider] = lambda: MockVisionProvider(
        _fixture("meal_multi_dish.json")
    )
    app.dependency_overrides[get_settings] = lambda: settings

    created = await _upload(client, auth_headers, "zero-day-retention")
    analysis_id = UUID(created.json()["data"]["id"])
    async with SessionLocal() as session:
        analysis = await session.get(MealAnalysisSession, analysis_id)
        assert analysis is not None
        image = await session.get(MealImage, analysis.image_id)
        assert image is not None
        object_path = storage.root / Path(*image.object_key.split("/"))
        assert object_path.exists()
        assert image.deleted_at is None

    confirmed = await client.post(
        f"/api/v1/meals/analyses/{analysis_id}/confirm",
        headers=auth_headers,
        json={
            "meal_type": "lunch",
            "eaten_at": f"{date.today().isoformat()}T12:00:00+08:00",
        },
    )
    assert confirmed.status_code == 201
    assert not object_path.exists()
    async with SessionLocal() as session:
        analysis = await session.get(MealAnalysisSession, analysis_id)
        assert analysis is not None
        image = await session.get(MealImage, analysis.image_id)
        assert image is not None
        assert image.deleted_at is not None


async def test_daily_limit_prevents_unbounded_provider_calls(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    storage = LocalStorageProvider(tmp_path / "private")
    settings = Settings(
        upload_dir=str(storage.root),
        vision_daily_limit=1,
    )
    app.dependency_overrides[get_private_storage] = lambda: storage
    app.dependency_overrides[get_vision_provider] = lambda: MockVisionProvider(
        _fixture("meal_multi_dish.json")
    )
    app.dependency_overrides[get_settings] = lambda: settings

    first = await _upload(client, auth_headers, "daily-limit-1")
    second = await _upload(client, auth_headers, "daily-limit-2")

    assert first.status_code == 202
    assert second.status_code == 429
    assert second.json()["error"]["code"] == "vision_daily_limit_reached"
    async with SessionLocal() as session:
        usage_count = await session.scalar(select(func.count(AIUsageLog.id)))
        assert usage_count == 1
