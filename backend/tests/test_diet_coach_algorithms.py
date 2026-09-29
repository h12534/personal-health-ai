from datetime import date, timedelta
from decimal import Decimal
from uuid import uuid4

from app.models.weight_log import WeightLog
from app.services.coach_safety_service import CoachSafetyService
from app.services.intent_classifier import IntentClassifier
from app.services.nutrition_target_service import NutritionTargetCalculator, TargetInputs
from app.services.weight_trend_service import WeightTrendCalculator


def _inputs(phase: str = "fat_loss") -> TargetInputs:
    return TargetInputs(
        weight_kg=Decimal("100"),
        target_weight_kg=Decimal("75"),
        height_cm=Decimal("176"),
        age=24,
        sex="male",
        activity_level="moderate",
        phase=phase,
    )


def test_daily_target_uses_phase_safety_and_adjusted_weight_protein() -> None:
    fat_loss = NutritionTargetCalculator.calculate(_inputs("fat_loss"), date(2026, 9, 1))
    maintenance = NutritionTargetCalculator.calculate(_inputs("maintenance"), date(2026, 9, 1))
    gain = NutritionTargetCalculator.calculate(_inputs("muscle_gain"), date(2026, 9, 1))

    assert fat_loss.energy_target_kcal >= int(fat_loss.formula_tdee_kcal * 0.8)
    assert fat_loss.energy_target_kcal < maintenance.energy_target_kcal < gain.energy_target_kcal
    assert fat_loss.protein_target_g == Decimal("130")
    assert Decimal("0") <= fat_loss.deficit_percent <= Decimal("20")


def test_weight_plateau_requires_enough_data_and_adherence() -> None:
    as_of = date(2026, 9, 28)
    user_id = uuid4()
    logs = [
        WeightLog(
            user_id=user_id,
            measured_on=as_of - timedelta(days=27 - index),
            weight_kg=Decimal("90.0") + Decimal(index % 2) * Decimal("0.05"),
        )
        for index in range(28)
    ]
    incomplete = WeightTrendCalculator.calculate(logs[:8], as_of, Decimal("1"))
    low_adherence = WeightTrendCalculator.calculate(logs, as_of, Decimal("0.50"))
    eligible = WeightTrendCalculator.calculate(logs, as_of, Decimal("0.90"))

    assert incomplete.plateau is False
    assert incomplete.plateau_eligible is False
    assert low_adherence.plateau is False
    assert eligible.plateau is True
    assert eligible.observations_14d == 14


def test_intent_and_safety_are_deterministic_for_high_risk_requests() -> None:
    assert IntentClassifier.classify("我胸痛而且呼吸困难") == "emergency_health"
    assert IntentClassifier.classify("严重低血糖而且意识异常") == "emergency_health"
    emergency = CoachSafetyService.evaluate("emergency_health", "我胸痛")
    assert emergency.blocked is True
    assert emergency.message is not None and "120" in emergency.message

    assert IntentClassifier.classify("昨晚暴食了，今天饿一天补偿吗") == "overeating_recovery"
    recovery = CoachSafetyService.evaluate("overeating_recovery", "今天饿一天")
    assert recovery.blocked is True
    assert recovery.message is not None and "不要" in recovery.message

    assert IntentClassifier.classify("食堂午饭吃什么") == "canteen_choice"
    assert IntentClassifier.classify("便利店怎么搭配") == "restaurant_choice"
    assert IntentClassifier.classify("减肥药剂量怎么加") == "unsupported_medical"
    assert CoachSafetyService.evaluate("general_chat", "吃多后跑步补偿").blocked is True
