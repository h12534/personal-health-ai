from decimal import ROUND_HALF_UP, Decimal

from app.schemas.training import ProgressionSuggestion


class ProgressionService:
    UPPER_PATTERNS = {"horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull"}
    LOWER_PATTERNS = {"squat", "hinge", "lunge"}

    @classmethod
    def suggest(
        cls,
        *,
        weight_kg: Decimal,
        reps: list[int],
        rir: list[Decimal | None],
        target_sets: int,
        target_rep_min: int,
        target_rep_max: int,
        movement_pattern: str,
        recovery_status: str = "normal",
        consecutive_declines: int = 0,
    ) -> ProgressionSuggestion:
        complete = len(reps) >= target_sets
        average_rir_values = [value for value in rir if value is not None]
        average_rir = (
            sum(average_rir_values, Decimal("0")) / len(average_rir_values)
            if average_rir_values
            else None
        )
        high_effort = average_rir is not None and average_rir <= Decimal("1")
        if recovery_status == "reduced" and consecutive_declines >= 2:
            reduced = (weight_kg * Decimal("0.95")).quantize(Decimal("0.5"), rounding=ROUND_HALF_UP)
            return ProgressionSuggestion(
                action="reduce_load",
                suggested_weight_kg=max(Decimal("0"), reduced),
                suggested_sets=target_sets,
                reason="连续两次表现下降且恢复偏低，保守降低约 5% 负荷；不触发一次性大幅 deload。",
            )
        if complete and all(value >= target_rep_max for value in reps[:target_sets]):
            if average_rir is None or average_rir >= Decimal("2"):
                increment = cls._increment(weight_kg, movement_pattern)
                return ProgressionSuggestion(
                    action="increase_weight",
                    suggested_weight_kg=weight_kg + increment,
                    suggested_sets=target_sets,
                    reason="所有工作组达到次数上限且保留约 2 次以上余力，进入双进阶的加重步骤。",
                )
        if not complete or min(reps, default=0) < target_rep_min or high_effort:
            return ProgressionSuggestion(
                action="maintain",
                suggested_weight_kg=weight_kg,
                suggested_sets=target_sets,
                reason="目标次数尚未稳定完成或接近力竭，下次保持重量并优先改善完成度。",
            )
        return ProgressionSuggestion(
            action="increase_reps",
            suggested_weight_kg=weight_kg,
            suggested_sets=target_sets,
            reason="重量保持不变，在目标范围内逐组增加次数。",
        )

    @classmethod
    def _increment(cls, weight_kg: Decimal, movement_pattern: str) -> Decimal:
        if movement_pattern in cls.LOWER_PATTERNS:
            return Decimal("2.5") if weight_kg < Decimal("100") else Decimal("5")
        if movement_pattern in cls.UPPER_PATTERNS:
            return Decimal("1") if weight_kg < Decimal("30") else Decimal("2.5")
        return Decimal("1")
