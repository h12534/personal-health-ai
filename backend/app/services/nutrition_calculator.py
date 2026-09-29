from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from app.core.errors import AppError
from app.models.food import FoodItem

THREE_PLACES = Decimal("0.001")
SUPPORTED_UNITS = {"g", "ml", "serving", "piece", "bowl", "cup", "custom"}


def quantize_nutrition(value: Decimal) -> Decimal:
    return value.quantize(THREE_PLACES, rounding=ROUND_HALF_UP)


@dataclass(frozen=True, slots=True)
class NutritionValues:
    weight_g: Decimal
    calories: Decimal
    protein: Decimal
    carbs: Decimal
    fat: Decimal
    fiber: Decimal


class PortionConversionService:
    @staticmethod
    def to_grams(food: FoodItem, amount: Decimal, unit: str) -> Decimal:
        if amount <= 0 or amount > Decimal("100000"):
            raise AppError("invalid_portion", "Amount is outside the supported range.", 422)
        if unit not in SUPPORTED_UNITS:
            raise AppError("unsupported_unit", "This portion unit is not supported.", 422)
        if unit == "g":
            return quantize_nutrition(amount)
        if food.serving_weight_g is None:
            raise AppError(
                "portion_conversion_unavailable",
                "This food does not define a conversion for the requested unit.",
                422,
            )
        if unit != "serving" and unit != food.serving_unit:
            raise AppError(
                "portion_conversion_unavailable",
                f"This food supports g, serving, and {food.serving_unit}.",
                422,
            )
        return quantize_nutrition(amount * food.serving_weight_g)


class NutritionCalculator:
    @staticmethod
    def calculate(food: FoodItem, amount: Decimal, unit: str) -> NutritionValues:
        weight_g = PortionConversionService.to_grams(food, amount, unit)
        factor = weight_g / Decimal("100")
        return NutritionValues(
            weight_g=weight_g,
            calories=quantize_nutrition(food.calories_per_100g * factor),
            protein=quantize_nutrition(food.protein_per_100g * factor),
            carbs=quantize_nutrition(food.carbs_per_100g * factor),
            fat=quantize_nutrition(food.fat_per_100g * factor),
            fiber=quantize_nutrition(food.fiber_per_100g * factor),
        )
