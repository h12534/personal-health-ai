from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal


@dataclass(frozen=True, slots=True)
class OneRepMax:
    epley: Decimal
    brzycki: Decimal
    estimate: Decimal
    confidence: str


def volume_load(weight_kg: Decimal, reps: int, set_type: str, completed: bool = True) -> Decimal:
    if not completed or set_type == "warmup":
        return Decimal("0")
    return (weight_kg * reps).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def estimate_one_rep_max(weight_kg: Decimal, reps: int) -> OneRepMax:
    if weight_kg <= 0 or reps <= 0:
        zero = Decimal("0")
        return OneRepMax(zero, zero, zero, "low")
    epley = weight_kg * (Decimal("1") + Decimal(reps) / Decimal("30"))
    denominator = Decimal("37") - Decimal(reps)
    brzycki = weight_kg if denominator <= 0 else weight_kg * Decimal("36") / denominator
    estimate = (epley + brzycki) / Decimal("2")
    confidence = "high" if reps <= 8 else "normal" if reps <= 12 else "low"
    return OneRepMax(
        epley.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP),
        brzycki.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP),
        estimate.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP),
        confidence,
    )
