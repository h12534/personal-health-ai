from dataclasses import dataclass
from decimal import Decimal

from app.models.food import FoodItem
from app.services.nutrition_calculator import NutritionCalculator, NutritionValues


@dataclass(frozen=True, slots=True)
class NutritionRange:
    center: NutritionValues
    minimum: NutritionValues
    maximum: NutritionValues


class NutritionRangeService:
    @staticmethod
    def calculate(
        food: FoodItem,
        estimated_weight_g: Decimal,
        min_weight_g: Decimal,
        max_weight_g: Decimal,
    ) -> NutritionRange:
        return NutritionRange(
            center=NutritionCalculator.calculate(food, estimated_weight_g, "g"),
            minimum=NutritionCalculator.calculate(food, min_weight_g, "g"),
            maximum=NutritionCalculator.calculate(food, max_weight_g, "g"),
        )
