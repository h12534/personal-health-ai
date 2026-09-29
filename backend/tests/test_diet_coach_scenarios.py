from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal

from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.diet_coach import PersonalEnergyModel
from app.models.health_profile import HealthProfile
from app.models.meal import MealLog
from app.models.nutrition_goal import NutritionGoal
from app.models.user import User
from app.models.weight_log import WeightLog
from app.services.diet_adherence_service import DietAdherenceService
from app.services.diet_adjustment_service import DietAdjustmentService
from app.services.next_meal_planner import NextMealPlanner
from app.services.tdee_estimator import TDEEEstimator
from app.services.weight_trend_service import WeightTrendService


async def test_28_day_plateau_observed_tdee_adjustment_and_cooldown(
    auth_headers: dict[str, str],
) -> None:
    del auth_headers
    today = date.today()
    async with SessionLocal() as session:
        user = await session.scalar(select(User).limit(1))
        assert user is not None
        session.add(
            HealthProfile(
                user_id=user.id,
                birth_date=date(2000, 1, 1),
                sex="male",
                height_cm=Decimal("176"),
                target_weight_kg=Decimal("78"),
                activity_level="moderate",
                current_goal_phase="fat_loss",
                adjustment_cooldown_days=14,
            )
        )
        goal = NutritionGoal(
            user_id=user.id,
            effective_from=today - timedelta(days=27),
            calorie_target=2200,
            protein_target_g=Decimal("140"),
            carbs_target_g=Decimal("250"),
            fat_target_g=Decimal("70"),
            fiber_target_g=Decimal("25"),
            water_target_ml=2500,
            source="test",
        )
        session.add(goal)
        for index in range(28):
            day = today - timedelta(days=27 - index)
            session.add(
                WeightLog(
                    user_id=user.id,
                    measured_on=day,
                    weight_kg=Decimal("90") + Decimal(index % 2) * Decimal("0.02"),
                )
            )
            for hour, meal_type in ((8, "breakfast"), (18, "dinner")):
                session.add(
                    MealLog(
                        user_id=user.id,
                        meal_type=meal_type,
                        eaten_at=datetime.combine(day, time(hour), UTC),
                        source="test",
                        total_calories=Decimal("1100"),
                        total_protein=Decimal("70"),
                        total_carbs=Decimal("125"),
                        total_fat=Decimal("35"),
                        total_fiber=Decimal("12.5"),
                    )
                )
        await session.commit()

        adherence = await DietAdherenceService(session).calculate(user.id, today, 28)
        trend = await WeightTrendService(session).build(user.id, today, adherence.overall_rate)
        energy = await TDEEEstimator(session).estimate(user.id, today)
        replayed_energy = await TDEEEstimator(session).estimate(user.id, today)
        next_meal = await NextMealPlanner(session).plan(user.id, today, hour=20)
        suggestion = await DietAdjustmentService(session).suggest(user.id, today)

        assert adherence.overall_rate >= Decimal("0.98")
        assert trend.plateau is True
        assert energy.observed_tdee is not None
        assert replayed_energy.blended_tdee == energy.blended_tdee
        assert (
            len(
                list(
                    (
                        await session.scalars(
                            select(PersonalEnergyModel).where(
                                PersonalEnergyModel.user_id == user.id,
                                PersonalEnergyModel.calculated_on == today,
                            )
                        )
                    ).all()
                )
            )
            == 1
        )
        assert energy.sample_days >= 27
        assert next_meal.over_target is True
        assert any("不跳餐" in item for item in next_meal.strategy)
        assert suggestion is not None
        assert suggestion.proposed_calorie_target == 2050

        accepted = await DietAdjustmentService(session).accept(
            user.id, suggestion.id, "scenario-adjustment-accept"
        )
        replay = await DietAdjustmentService(session).accept(
            user.id, suggestion.id, "scenario-adjustment-accept"
        )
        assert accepted.resulting_goal_id == replay.resulting_goal_id
        assert accepted.status == "accepted"
        assert (
            await DietAdjustmentService(session).suggest(user.id, today + timedelta(days=1)) is None
        )
