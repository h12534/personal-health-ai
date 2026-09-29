from dataclasses import dataclass
from datetime import date
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.nutrition_repository import NutritionGoalRepository
from app.repositories.profile_repository import ProfileRepository
from app.repositories.weight_repository import WeightRepository
from app.schemas.diet_coach import DailyTargetRead

ACTIVITY_FACTORS = {
    "sedentary": Decimal("1.20"),
    "light": Decimal("1.35"),
    "moderate": Decimal("1.50"),
    "high": Decimal("1.70"),
}
PHASE_ADJUSTMENTS = {
    "fat_loss": Decimal("-0.15"),
    "maintenance": Decimal("0"),
    "recomposition": Decimal("-0.05"),
    "muscle_gain": Decimal("0.08"),
}


@dataclass(frozen=True)
class TargetInputs:
    weight_kg: Decimal
    target_weight_kg: Decimal | None
    height_cm: Decimal
    age: int
    sex: str | None
    activity_level: str | None
    phase: str


class MifflinStJeor:
    @staticmethod
    def calculate(inputs: TargetInputs) -> Decimal:
        sex_offset = Decimal("5") if inputs.sex == "male" else Decimal("-161")
        if inputs.sex not in {"male", "female"}:
            sex_offset = Decimal("-78")
        return (
            Decimal("10") * inputs.weight_kg
            + Decimal("6.25") * inputs.height_cm
            - Decimal("5") * inputs.age
            + sex_offset
        )


class ProteinTargetStrategy:
    @staticmethod
    def adjusted_weight(inputs: TargetInputs) -> Decimal:
        if inputs.target_weight_kg and inputs.weight_kg > inputs.target_weight_kg * Decimal("1.2"):
            return inputs.target_weight_kg + (inputs.weight_kg - inputs.target_weight_kg) * Decimal(
                "0.25"
            )
        return inputs.weight_kg

    @classmethod
    def target(cls, inputs: TargetInputs) -> Decimal:
        multiplier = {
            "fat_loss": Decimal("1.6"),
            "maintenance": Decimal("1.4"),
            "recomposition": Decimal("1.7"),
            "muscle_gain": Decimal("1.8"),
        }.get(inputs.phase, Decimal("1.6"))
        value = cls.adjusted_weight(inputs) * multiplier
        return min(Decimal("220"), max(Decimal("75"), value)).quantize(Decimal("1"))


class NutritionSafetyPolicy:
    MAX_DEFICIT = Decimal("0.20")

    @staticmethod
    def calorie_floor(sex: str | None) -> int:
        return 1500 if sex == "male" else 1200 if sex == "female" else 1350

    @classmethod
    def apply(cls, tdee: Decimal, proposed: Decimal, sex: str | None) -> tuple[int, list[str]]:
        notes = ["目标是估算值，应依据至少 14 天趋势复核，而不是依据单日体重修改。"]
        minimum_by_deficit = tdee * (Decimal("1") - cls.MAX_DEFICIT)
        floor = Decimal(cls.calorie_floor(sex))
        safe = max(proposed, minimum_by_deficit, floor)
        if safe > proposed:
            notes.append("已应用保守热量下限，避免过大的能量缺口。")
        safe = min(safe, Decimal("5000"))
        rounded = int((safe / Decimal("25")).quantize(Decimal("1"), rounding=ROUND_HALF_UP) * 25)
        return rounded, notes


class NutritionTargetCalculator:
    @staticmethod
    def calculate(inputs: TargetInputs, on_date: date) -> DailyTargetRead:
        phase = inputs.phase if inputs.phase in PHASE_ADJUSTMENTS else "fat_loss"
        normalized = TargetInputs(**{**inputs.__dict__, "phase": phase})
        bmr = MifflinStJeor.calculate(normalized)
        factor = ACTIVITY_FACTORS.get(inputs.activity_level or "", Decimal("1.30"))
        tdee = bmr * factor
        adjustment = PHASE_ADJUSTMENTS[phase]
        calories, notes = NutritionSafetyPolicy.apply(tdee, tdee * (1 + adjustment), inputs.sex)
        protein = ProteinTargetStrategy.target(normalized)
        adjusted_weight = ProteinTargetStrategy.adjusted_weight(normalized)
        fat = max(Decimal("40"), adjusted_weight * Decimal("0.7")).quantize(Decimal("1"))
        remaining = max(Decimal("80"), (Decimal(calories) - protein * 4 - fat * 9) / 4)
        deficit = max(Decimal("0"), (tdee - Decimal(calories)) / tdee)
        return DailyTargetRead(
            date=on_date,
            phase=phase,
            bmr_kcal=int(bmr.quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
            formula_tdee_kcal=int(tdee.quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
            energy_target_kcal=calories,
            deficit_percent=(deficit * 100).quantize(Decimal("0.1")),
            protein_target_g=protein,
            carbs_target_g=remaining.quantize(Decimal("1")),
            fat_target_g=fat,
            carb_range_min_g=(remaining * Decimal("0.85")).quantize(Decimal("1")),
            carb_range_max_g=(remaining * Decimal("1.15")).quantize(Decimal("1")),
            fat_range_min_g=(fat * Decimal("0.85")).quantize(Decimal("1")),
            fat_range_max_g=(fat * Decimal("1.15")).quantize(Decimal("1")),
            fiber_target_g=Decimal("25"),
            water_target_ml=2500,
            source="mifflin_st_jeor+phase_policy_v1",
            safety_notes=notes,
        )


class NutritionTargetService:
    def __init__(self, session: AsyncSession) -> None:
        self.profiles = ProfileRepository(session)
        self.weights = WeightRepository(session)
        self.goals = NutritionGoalRepository(session)

    async def daily(
        self,
        user_id: UUID,
        on_date: date | None = None,
        prefer_active_goal: bool = True,
    ) -> DailyTargetRead:
        profile = await self.profiles.by_user(user_id)
        reference = on_date or date.today()
        weights = await self.weights.list_for_user(user_id, date_to=reference)
        weight = weights[-1].weight_kg if weights else Decimal("100")
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
        height = profile.height_cm if profile and profile.height_cm else Decimal("176")
        target = NutritionTargetCalculator.calculate(
            TargetInputs(
                weight_kg=weight,
                target_weight_kg=profile.target_weight_kg if profile else None,
                height_cm=height,
                age=max(13, age),
                sex=profile.sex if profile else None,
                activity_level=profile.activity_level if profile else None,
                phase=profile.current_goal_phase if profile else "fat_loss",
            ),
            reference,
        )
        if profile is None or not weights or not (profile and profile.height_cm):
            target.safety_notes.append(
                "部分个人资料缺失，当前为低置信度初始估算；补充身高和晨重后会自动更新。"
            )
        if prefer_active_goal:
            goal = await self.goals.current(user_id, reference)
            if goal is not None:
                carbs = goal.carbs_target_g or target.carbs_target_g
                fat = goal.fat_target_g or target.fat_target_g
                target = target.model_copy(
                    update={
                        "energy_target_kcal": goal.calorie_target,
                        "protein_target_g": goal.protein_target_g,
                        "carbs_target_g": carbs,
                        "fat_target_g": fat,
                        "carb_range_min_g": (carbs * Decimal("0.85")).quantize(Decimal("1")),
                        "carb_range_max_g": (carbs * Decimal("1.15")).quantize(Decimal("1")),
                        "fat_range_min_g": (fat * Decimal("0.85")).quantize(Decimal("1")),
                        "fat_range_max_g": (fat * Decimal("1.15")).quantize(Decimal("1")),
                        "fiber_target_g": goal.fiber_target_g,
                        "water_target_ml": goal.water_target_ml,
                        "source": f"nutrition_goal:{goal.source}",
                    }
                )
        return target
