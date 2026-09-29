from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.diet_coach import PersonalEnergyModel
from app.repositories.weight_repository import WeightRepository
from app.schemas.diet_coach import EnergyModelRead
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.nutrition_target_service import NutritionTargetService


class TDEEEstimator:
    MIN_DAYS = 21

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.weights = WeightRepository(session)
        self.daily = DailyNutritionService(session)
        self.targets = NutritionTargetService(session)

    async def estimate(self, user_id: UUID, as_of: date | None = None) -> EnergyModelRead:
        reference = as_of or date.today()
        target = await self.targets.daily(user_id, reference)
        start = reference - timedelta(days=27)
        nutrition = await self.daily.range(user_id, start, reference)
        complete = [day for day in nutrition if day.meal_count >= 2]
        weights = await self.weights.list_for_user(user_id, start, reference)
        completeness = Decimal(len(complete)) / Decimal(28)
        observed: int | None = None
        confidence = Decimal("0")
        explanation = "使用公式 TDEE；需要至少 21 个较完整记录日和覆盖窗口两端的体重。"
        if len(complete) >= self.MIN_DAYS and len(weights) >= 8:
            first_group = weights[: min(4, len(weights))]
            last_group = weights[-min(4, len(weights)) :]
            first_avg = sum(
                (Decimal(item.weight_kg) for item in first_group), Decimal("0")
            ) / Decimal(len(first_group))
            last_avg = sum(
                (Decimal(item.weight_kg) for item in last_group), Decimal("0")
            ) / Decimal(len(last_group))
            span = max(1, (last_group[-1].measured_on - first_group[0].measured_on).days)
            avg_intake = sum(
                (Decimal(day.totals.calories) for day in complete), Decimal("0")
            ) / Decimal(len(complete))
            observed_value = avg_intake - (last_avg - first_avg) * Decimal("7700") / Decimal(span)
            lower = Decimal(target.formula_tdee_kcal) * Decimal("0.75")
            upper = Decimal(target.formula_tdee_kcal) * Decimal("1.25")
            observed = int(
                min(upper, max(lower, observed_value)).quantize(
                    Decimal("1"), rounding=ROUND_HALF_UP
                )
            )
            confidence = min(Decimal("0.85"), completeness * Decimal("0.8"))
            explanation = "由 28 天平均摄入与体重趋势估算，并与公式值保守混合。"
        formula = target.formula_tdee_kcal
        blended = (
            formula
            if observed is None
            else int(
                (
                    Decimal(formula) * (Decimal("1") - confidence) + Decimal(observed) * confidence
                ).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
            )
        )
        result = EnergyModelRead(
            as_of=reference,
            formula_tdee=formula,
            observed_tdee=observed,
            blended_tdee=blended,
            confidence=confidence.quantize(Decimal("0.001")),
            sample_days=len(complete),
            completeness=completeness.quantize(Decimal("0.001")),
            explanation=explanation,
        )
        stored = await self.session.scalar(
            select(PersonalEnergyModel).where(
                PersonalEnergyModel.user_id == user_id,
                PersonalEnergyModel.calculated_on == reference,
            )
        )
        evidence: dict[str, object] = {
            "window_days": 28,
            "complete_days": len(complete),
            "weight_samples": len(weights),
        }
        if stored is None:
            stored = PersonalEnergyModel(
                user_id=user_id,
                calculated_on=reference,
                formula_tdee=formula,
                observed_tdee=observed,
                blended_tdee=blended,
                confidence=result.confidence,
                sample_days=result.sample_days,
                completeness=result.completeness,
                evidence_snapshot=evidence,
            )
            self.session.add(stored)
        else:
            stored.formula_tdee = formula
            stored.observed_tdee = observed
            stored.blended_tdee = blended
            stored.confidence = result.confidence
            stored.sample_days = result.sample_days
            stored.completeness = result.completeness
            stored.evidence_snapshot = evidence
        await self.session.commit()
        return result
