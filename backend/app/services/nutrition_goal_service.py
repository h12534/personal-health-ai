from datetime import date, datetime, timedelta
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
        from app.services.nutrition_target_service import NutritionTargetService

        target = await NutritionTargetService(self.session).daily(
            user_id, on_date, prefer_active_goal=False
        )
        return NutritionGoalWrite(
            effective_from=target.date,
            calorie_target=target.energy_target_kcal,
            protein_target_g=target.protein_target_g,
            carbs_target_g=target.carbs_target_g,
            fat_target_g=target.fat_target_g,
            fiber_target_g=target.fiber_target_g,
            water_target_ml=target.water_target_ml,
            source="program_suggestion",
            reason="Programmatic Mifflin-St Jeor target with phase and nutrition safety policies.",
        )

    @staticmethod
    def _local_today(timezone_name: str | None) -> date:
        try:
            timezone = ZoneInfo(timezone_name or "Asia/Shanghai")
        except ZoneInfoNotFoundError:
            timezone = ZoneInfo("UTC")
        return datetime.now(timezone).date()
