from datetime import date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.nutrition_goal import NutritionGoal
from app.repositories.nutrition_repository import NutritionGoalRepository
from app.repositories.profile_repository import ProfileRepository
from app.repositories.weight_repository import WeightRepository
from app.schemas.nutrition import NutritionGoalUpdate, NutritionGoalWrite


class NutritionGoalService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.goals = NutritionGoalRepository(session)
        self.profiles = ProfileRepository(session)
        self.weights = WeightRepository(session)

    async def current(self, user_id: UUID, on_date: date | None = None) -> NutritionGoal:
        reference = on_date
        if reference is None:
            profile = await self.profiles.by_user(user_id)
            reference = self._local_today(profile.timezone if profile else None)
        goal = await self.goals.current(user_id, reference)
        if goal is None:
            raise AppError("nutrition_goal_not_found", "No nutrition goal is active.", 404)
        return goal

    async def create(self, user_id: UUID, payload: NutritionGoalWrite) -> NutritionGoal:
        current = await self.goals.current(user_id, payload.effective_from)
        if current is not None:
            if current.effective_from == payload.effective_from:
                raise AppError(
                    "nutrition_goal_date_conflict",
                    "A nutrition goal already starts on this date.",
                    409,
                )
        next_goal = await self.goals.next_after(user_id, payload.effective_from)
        values = payload.model_dump()
        if next_goal is not None:
            if (
                payload.effective_to is not None
                and payload.effective_to >= next_goal.effective_from
            ):
                raise AppError(
                    "nutrition_goal_date_conflict",
                    "Goal dates overlap a later nutrition goal.",
                    409,
                )
            if payload.effective_to is None:
                values["effective_to"] = next_goal.effective_from - timedelta(days=1)
        if current is not None:
            current.effective_to = payload.effective_from - timedelta(days=1)
        goal = NutritionGoal(user_id=user_id, **values)
        self.session.add(goal)
        await self.session.commit()
        await self.session.refresh(goal)
        return goal

    async def update(
        self, user_id: UUID, goal_id: UUID, payload: NutritionGoalUpdate
    ) -> NutritionGoal:
        goal = await self.goals.by_id(user_id, goal_id)
        if goal is None:
            raise AppError("nutrition_goal_not_found", "Nutrition goal was not found.", 404)
        values = payload.model_dump(exclude_unset=True)
        proposed_end = values.get("effective_to", goal.effective_to)
        if proposed_end is not None and proposed_end < goal.effective_from:
            raise AppError("invalid_goal_dates", "Goal end date cannot precede start date.", 422)
        next_goal = await self.goals.next_after(user_id, goal.effective_from)
        if next_goal is not None and (
            proposed_end is None or proposed_end >= next_goal.effective_from
        ):
            raise AppError(
                "nutrition_goal_date_conflict",
                "Goal dates overlap a later nutrition goal.",
                409,
            )
        for field, value in values.items():
            setattr(goal, field, value)
        await self.session.commit()
        await self.session.refresh(goal)
        return goal

    async def suggested(self, user_id: UUID, on_date: date | None = None) -> NutritionGoalWrite:
        profile = await self.profiles.by_user(user_id)
        reference = on_date or self._local_today(profile.timezone if profile else None)
        weights = await self.weights.list_for_user(user_id, date_to=reference)
        weight = float(weights[-1].weight_kg) if weights else 100.0
        height = float(profile.height_cm) if profile and profile.height_cm else 176.0
        age = 21
        if profile and profile.birth_date:
            age = (
                reference.year
                - profile.birth_date.year
                - (
                    (reference.month, reference.day)
                    < (profile.birth_date.month, profile.birth_date.day)
                )
            )
        sex = profile.sex if profile else None
        sex_offset = 5 if sex == "male" else -161 if sex == "female" else -78
        bmr = 10 * weight + 6.25 * height - 5 * age + sex_offset
        activity_key = (profile.activity_level if profile else None) or "unknown"
        activity_factor = {
            "sedentary": 1.2,
            "light": 1.35,
            "moderate": 1.5,
            "high": 1.7,
        }.get(activity_key, 1.3)
        minimum = 1600 if sex == "male" else 1400 if sex == "female" else 1500
        calories = int(round(max(minimum, min(3500, bmr * activity_factor * 0.8)) / 50) * 50)
        protein = Decimal(str(max(90, min(220, weight * 1.6)))).quantize(
            Decimal("1"), rounding=ROUND_HALF_UP
        )
        return NutritionGoalWrite(
            effective_from=reference,
            calorie_target=calories,
            protein_target_g=protein,
            carbs_target_g=None,
            fat_target_g=None,
            fiber_target_g=Decimal("25"),
            water_target_ml=2500,
            source="program_suggestion",
            reason="Conservative initial estimate; review against 7–14 day trends before changing.",
        )

    @staticmethod
    def _local_today(timezone_name: str | None) -> date:
        try:
            timezone = ZoneInfo(timezone_name or "Asia/Shanghai")
        except ZoneInfoNotFoundError:
            timezone = ZoneInfo("UTC")
        return datetime.now(timezone).date()
