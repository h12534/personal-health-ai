from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

import pytest
from httpx import AsyncClient

from app.db.session import SessionLocal
from app.scripts.seed_exercises import seed_exercises
from app.services.progression_service import ProgressionService
from app.services.recovery_service import RecoveryRuleEngine
from app.services.training_metrics import estimate_one_rep_max, volume_load
from app.services.training_plan_service import PlanRescheduleService
from app.services.training_safety_service import TrainingSafetyService


@pytest.mark.anyio
async def test_exercise_seed_is_idempotent_and_searchable(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    async with SessionLocal() as session:
        first = await seed_exercises(session)
        second = await seed_exercises(session)
    assert first == (28, 0)
    assert second == (0, 28)
    response = await client.get(
        "/api/v1/exercises/search", params={"q": "深蹲"}, headers=auth_headers
    )
    assert response.status_code == 200
    assert {item["name"] for item in response.json()["data"]} >= {"深蹲", "史密斯深蹲"}


@pytest.mark.anyio
async def test_plan_generator_and_crud(client: AsyncClient, auth_headers: dict[str, str]) -> None:
    response = await client.post(
        "/api/v1/training/plans/generate",
        json={
            "goal": "fat_loss_muscle_retention",
            "experience": "beginner",
            "days_per_week": 3,
            "equipment": ["machine", "dumbbell", "cable", "bodyweight"],
            "session_duration_min": 60,
            "limitations": [],
            "preferences": ["腿举"],
        },
        headers=auth_headers,
    )
    assert response.status_code == 201
    plan = response.json()["data"]
    assert plan["sessions_per_week"] == 3
    assert len(plan["days"]) == 3
    assert all(len(day["exercises"]) >= 4 for day in plan["days"])
    assert all(
        exercise["target_rir"] in ("3", "3.0")
        for day in plan["days"]
        for exercise in day["exercises"]
    )
    first_exercise = plan["days"][0]["exercises"][0]
    adjustment = {
        "exercise_id": first_exercise["exercise_id"],
        "suggested_weight_kg": 42.5,
        "reason": "三组均达到目标次数且保留两次余力。",
        "idempotency_key": "progression-apply-0001",
        "evidence_snapshot": {"reps": [12, 12, 12], "rir": [2, 2, 2]},
    }
    applied = await client.post(
        "/api/v1/training/adjustments/apply",
        json=adjustment,
        headers=auth_headers,
    )
    assert applied.status_code == 200
    assert Decimal(applied.json()["data"]["target_weight_kg"]) == Decimal("42.5")
    duplicate = await client.post(
        "/api/v1/training/adjustments/apply",
        json=adjustment,
        headers=auth_headers,
    )
    assert duplicate.status_code == 200
    assert duplicate.json()["data"]["id"] == applied.json()["data"]["id"]

    updated = await client.patch(
        f"/api/v1/training/plans/{plan['id']}",
        json={"name": "我的三日全身计划", "weeks": 10},
        headers=auth_headers,
    )
    assert updated.status_code == 200
    assert updated.json()["data"]["name"] == "我的三日全身计划"
    listed = await client.get("/api/v1/training/plans", headers=auth_headers)
    assert listed.json()["meta"]["count"] == 1


@pytest.mark.anyio
async def test_workout_set_idempotency_rir_volume_and_pr(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    exercises = await client.get("/api/v1/exercises", headers=auth_headers)
    bench = next(item for item in exercises.json()["data"] if item["name"] == "卧推")
    workout_id = "9dd6f08b-882b-4a74-8604-557e7d24be7f"
    started = datetime.now(UTC) - timedelta(minutes=45)
    created = await client.post(
        "/api/v1/workouts",
        json={
            "id": workout_id,
            "started_at": started.isoformat(),
            "idempotency_key": f"workout-{workout_id}",
        },
        headers=auth_headers,
    )
    assert created.status_code == 201
    for number in range(1, 4):
        set_id = f"00000000-0000-4000-8000-{number:012d}"
        payload = {
            "id": set_id,
            "exercise_id": bench["id"],
            "set_number": number,
            "set_type": "working",
            "weight_kg": 40,
            "reps": 12,
            "rir": 2,
            "idempotency_key": f"set-{set_id}",
        }
        response = await client.post(
            f"/api/v1/workouts/{workout_id}/sets",
            json=payload,
            headers=auth_headers,
        )
        assert response.status_code == 201
        assert Decimal(response.json()["data"]["rpe"]) == Decimal("8")
        duplicate = await client.post(
            f"/api/v1/workouts/{workout_id}/sets",
            json=payload,
            headers=auth_headers,
        )
        assert duplicate.json()["data"]["id"] == set_id

    warmup = await client.post(
        f"/api/v1/workouts/{workout_id}/sets",
        json={
            "exercise_id": bench["id"],
            "set_number": 4,
            "set_type": "warmup",
            "weight_kg": 20,
            "reps": 10,
            "rir": 5,
            "idempotency_key": "warmup-00000001",
        },
        headers=auth_headers,
    )
    assert warmup.status_code == 201
    completed = await client.post(
        f"/api/v1/workouts/{workout_id}/complete",
        json={"ended_at": datetime.now(UTC).isoformat(), "session_rpe": 7},
        headers=auth_headers,
    )
    assert completed.status_code == 200
    summary = completed.json()["data"]
    assert summary["effective_sets"] == 3
    assert Decimal(summary["volume_load"]) == Decimal("1440")
    assert {item["pr_type"] for item in summary["prs"]} == {
        "max_weight",
        "max_reps",
        "estimated_1rm",
        "volume",
    }


def test_volume_e1rm_and_progression_scenarios() -> None:
    assert volume_load(Decimal("40"), 10, "warmup") == 0
    assert volume_load(Decimal("40"), 10, "working") == Decimal("400.00")
    moderate = estimate_one_rep_max(Decimal("40"), 10)
    high_rep = estimate_one_rep_max(Decimal("40"), 16)
    assert moderate.estimate > Decimal("50")
    assert moderate.confidence == "normal"
    assert high_rep.confidence == "low"

    increase = ProgressionService.suggest(
        weight_kg=Decimal("40"),
        reps=[12, 12, 12],
        rir=[Decimal("2"), Decimal("2"), Decimal("2")],
        target_sets=3,
        target_rep_min=8,
        target_rep_max=12,
        movement_pattern="horizontal_push",
    )
    assert increase.action == "increase_weight"
    assert increase.suggested_weight_kg == Decimal("42.5")
    maintain = ProgressionService.suggest(
        weight_kg=Decimal("40"),
        reps=[8, 7, 6],
        rir=[Decimal("1"), Decimal("0"), Decimal("0")],
        target_sets=3,
        target_rep_min=8,
        target_rep_max=12,
        movement_pattern="horizontal_push",
    )
    assert maintain.action == "maintain"
    regression = ProgressionService.suggest(
        weight_kg=Decimal("100"),
        reps=[6, 5, 5],
        rir=[Decimal("0"), Decimal("0"), Decimal("0")],
        target_sets=3,
        target_rep_min=8,
        target_rep_max=12,
        movement_pattern="squat",
        recovery_status="reduced",
        consecutive_declines=2,
    )
    assert regression.action == "reduce_load"
    assert regression.suggested_weight_kg == Decimal("95.0")


def test_recovery_and_training_safety_scenarios() -> None:
    status, reasons = RecoveryRuleEngine.evaluate(
        sleep_duration_min=270,
        fatigue=5,
        last_session_rpe=Decimal("9"),
        resting_heart_rate=78,
        resting_heart_rate_baseline=Decimal("68"),
        pain_severity=2,
        recent_training_count=3,
    )
    assert status == "reduced"
    assert "睡眠少于 5 小时" in reasons
    punitive = TrainingSafetyService.evaluate("今天吃多了我要跑两个小时补回来")
    assert punitive.blocked and punitive.risk_level == "caution"
    pain = TrainingSafetyService.evaluate("膝盖剧烈疼痛而且无法负重")
    assert pain.blocked and pain.risk_level == "urgent"


def test_missed_workout_reschedules_without_double_session() -> None:
    monday = date(2026, 9, 28)
    result = PlanRescheduleService.reschedule(
        [monday, monday + timedelta(days=2), monday + timedelta(days=4)],
        monday + timedelta(days=2),
        [monday + timedelta(days=3), monday + timedelta(days=5)],
    )
    assert result == [
        monday,
        monday + timedelta(days=3),
        monday + timedelta(days=5),
    ]


@pytest.mark.anyio
async def test_health_sync_idempotency_sleep_recovery_and_permission(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    today = date.today().isoformat()
    payload = {
        "provider": "healthkit",
        "data_type": "steps",
        "source_record_id": f"healthkit-steps-{today}",
        "recorded_date": today,
        "steps": 6123,
    }
    first = await client.post("/api/v1/health/sync/summary", json=payload, headers=auth_headers)
    second = await client.post("/api/v1/health/sync/summary", json=payload, headers=auth_headers)
    assert first.json()["data"]["created"] is True
    assert second.json()["data"]["duplicate"] is True
    daily = await client.get("/api/v1/activity/daily", headers=auth_headers)
    assert daily.json()["data"]["steps"] == 6123
    assert daily.json()["data"]["step_goal"] < 10000

    end = datetime.now(UTC).replace(hour=6, minute=30)
    start = end - timedelta(hours=4, minutes=30)
    sleep = await client.post(
        "/api/v1/health/sync/summary",
        json={
            "provider": "healthkit",
            "data_type": "sleep",
            "source_record_id": "sleep-short-night",
            "sleep_start": start.isoformat(),
            "sleep_end": end.isoformat(),
            "sleep_stages": [{"stage": "core"}],
        },
        headers=auth_headers,
    )
    assert sleep.status_code == 200
    recovery = await client.post(
        "/api/v1/recovery/today",
        json={"subjective_fatigue": 5},
        headers=auth_headers,
    )
    assert recovery.json()["data"]["status"] == "reduced"

    permission = await client.put(
        "/api/v1/health/permissions",
        json={
            "data_type": "steps",
            "enabled": True,
            "authorization_status": "unknown",
        },
        headers=auth_headers,
    )
    assert permission.status_code == 200
    assert permission.json()["data"]["enabled"] is True


@pytest.mark.anyio
async def test_training_ai_structured_missed_workout_and_safety(
    client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    missed = await client.post(
        "/api/v1/ai/training/chat",
        json={"message": "今天没练，明天要不要双倍训练？"},
        headers=auth_headers,
    )
    assert missed.status_code == 200
    data = missed.json()["data"]
    assert data["intent"] == "missed_workout"
    assert "不需要补双倍训练" in data["message"]
    assert data["suggested_actions"][0]["type"] == "reschedule_plan"

    punitive = await client.post(
        "/api/v1/ai/training/chat",
        json={"message": "今天吃多了我要跑两个小时补回来"},
        headers=auth_headers,
    )
    safety = punitive.json()["data"]
    assert safety["provider"] == "safety_layer"
    assert safety["risk_level"] == "caution"
    assert "不会" in safety["message"]
