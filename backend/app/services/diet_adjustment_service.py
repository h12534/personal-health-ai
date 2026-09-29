import hashlib
import json
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.diet_coach import DietAdjustment
from app.models.nutrition_goal import NutritionGoal
from app.repositories.diet_coach_repository import DietCoachRepository
from app.repositories.nutrition_repository import NutritionGoalRepository
from app.repositories.profile_repository import ProfileRepository
from app.services.diet_adherence_service import DietAdherenceService
from app.services.weight_trend_service import WeightTrendService


class DietAdjustmentService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = DietCoachRepository(session)
        self.goals = NutritionGoalRepository(session)
        self.profiles = ProfileRepository(session)

    async def suggest(self, user_id: UUID, as_of: date | None = None) -> DietAdjustment | None:
        reference = as_of or date.today()
        profile = await self.profiles.by_user(user_id)
        goal = await self.goals.current(user_id, reference)
        if profile is None or goal is None:
            return None
        adherence = await DietAdherenceService(self.session).calculate(user_id, reference, 28)
        trend = await WeightTrendService(self.session).build(
            user_id, reference, adherence.overall_rate
        )
        if adherence.overall_rate < Decimal("0.80") or not trend.plateau_eligible:
            return None
        delta = 0
        reason = ""
        reason_code = ""
        if trend.plateau and profile.current_goal_phase == "fat_loss":
            delta = -150
            reason_code = "fat_loss_plateau"
            reason = "28 天体重趋势接近平台，且饮食记录完整度较高；建议小幅下调 150 kcal。"
        elif trend.weekly_rate_percent is not None and trend.weekly_rate_percent < Decimal("-1.0"):
            delta = 150
            reason_code = "loss_rate_too_fast"
            reason = "下降速度超过保守范围；建议小幅增加 150 kcal，优先维持训练和蛋白质。"
        if delta == 0:
            return None
        latest = await self.repo.latest_decided_adjustment(user_id)
        cooldown = max(7, profile.adjustment_cooldown_days)
        if (
            latest
            and latest.decided_at
            and latest.decided_at.date() + timedelta(days=cooldown) > reference
        ):
            return None
        proposed = max(1200, goal.calorie_target + delta)
        snapshot: dict[str, object] = {
            "as_of": reference.isoformat(),
            "goal_id": str(goal.id),
            "trend": trend.model_dump(mode="json"),
            "adherence": adherence.model_dump(mode="json"),
            "delta_kcal": delta,
        }
        digest = hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest()
        existing = await self.repo.adjustment_by_hash(user_id, digest)
        if existing:
            return existing
        adjustment = DietAdjustment(
            user_id=user_id,
            previous_goal_id=goal.id,
            previous_calorie_target=goal.calorie_target,
            proposed_calorie_target=proposed,
            previous_protein_target_g=goal.protein_target_g,
            proposed_protein_target_g=goal.protein_target_g,
            reason_code=reason_code,
            reason=reason,
            evidence_snapshot=snapshot,
            input_snapshot_hash=digest,
            evaluate_after=reference + timedelta(days=cooldown),
        )
        self.session.add(adjustment)
        await self.session.commit()
        await self.session.refresh(adjustment)
        return adjustment

    async def accept(self, user_id: UUID, adjustment_id: UUID, key: str) -> DietAdjustment:
        adjustment = await self.repo.adjustment(user_id, adjustment_id)
        if adjustment is None:
            raise AppError("adjustment_not_found", "Diet adjustment was not found.", 404)
        if adjustment.status == "accepted":
            return adjustment
        if adjustment.status != "pending":
            raise AppError(
                "adjustment_already_decided", "Diet adjustment was already decided.", 409
            )
        goal = await self.goals.current(user_id, date.today())
        if goal is None or goal.id != adjustment.previous_goal_id:
            raise AppError(
                "adjustment_stale", "The active goal changed; request a new review.", 409
            )
        effective = date.today() + timedelta(days=1)
        existing = await self.goals.current(user_id, effective)
        if existing and existing.effective_from == effective:
            raise AppError("nutrition_goal_date_conflict", "A goal already starts tomorrow.", 409)
        goal.effective_to = effective - timedelta(days=1)
        new_goal = NutritionGoal(
            user_id=user_id,
            effective_from=effective,
            calorie_target=adjustment.proposed_calorie_target,
            protein_target_g=adjustment.proposed_protein_target_g,
            carbs_target_g=goal.carbs_target_g,
            fat_target_g=goal.fat_target_g,
            fiber_target_g=goal.fiber_target_g,
            water_target_ml=goal.water_target_ml,
            source="approved_adjustment",
            reason=adjustment.reason,
        )
        self.session.add(new_goal)
        await self.session.flush()
        adjustment.status = "accepted"
        adjustment.approved_by = "user"
        adjustment.decided_at = datetime.now(UTC)
        adjustment.resulting_goal_id = new_goal.id
        adjustment.idempotency_key = key
        await self.session.commit()
        await self.session.refresh(adjustment)
        return adjustment

    async def decline(self, user_id: UUID, adjustment_id: UUID, key: str) -> DietAdjustment:
        adjustment = await self.repo.adjustment(user_id, adjustment_id)
        if adjustment is None:
            raise AppError("adjustment_not_found", "Diet adjustment was not found.", 404)
        if adjustment.status == "declined":
            return adjustment
        if adjustment.status != "pending":
            raise AppError(
                "adjustment_already_decided", "Diet adjustment was already decided.", 409
            )
        adjustment.status = "declined"
        adjustment.approved_by = "user"
        adjustment.decided_at = datetime.now(UTC)
        adjustment.idempotency_key = key
        await self.session.commit()
        await self.session.refresh(adjustment)
        return adjustment
