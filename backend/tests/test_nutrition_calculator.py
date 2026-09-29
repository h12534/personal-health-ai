from decimal import Decimal

import pytest

from app.core.errors import AppError
from app.models.food import FoodItem
from app.services.nutrition_calculator import NutritionCalculator


def _rice() -> FoodItem:
    return FoodItem(
        name="米饭",
        normalized_name="米饭",
        category="grain",
        source="database",
        source_id="rice",
        is_custom=False,
        calories_per_100g=Decimal("130"),
        protein_per_100g=Decimal("2.7"),
        carbs_per_100g=Decimal("28.2"),
        fat_per_100g=Decimal("0.3"),
        fiber_per_100g=Decimal("0.4"),
    )


@pytest.mark.parametrize(
    ("grams", "calories", "protein"),
    [("100", "130.000", "2.700"), ("150", "195.000", "4.050"), ("200", "260.000", "5.400")],
)
def test_calculation_scales_100g_150g_200g(grams: str, calories: str, protein: str) -> None:
    result = NutritionCalculator.calculate(_rice(), Decimal(grams), "g")
    assert result.calories == Decimal(calories)
    assert result.protein == Decimal(protein)


def test_piece_and_ml_use_food_serving_conversion() -> None:
    egg = _rice()
    egg.serving_unit = "piece"
    egg.serving_weight_g = Decimal("50")
    result = NutritionCalculator.calculate(egg, Decimal("2"), "piece")
    assert result.weight_g == Decimal("100.000")

    milk = _rice()
    milk.serving_unit = "ml"
    milk.serving_weight_g = Decimal("1.03")
    result = NutritionCalculator.calculate(milk, Decimal("300"), "ml")
    assert result.weight_g == Decimal("309.000")


def test_unsupported_conversion_fails_explicitly() -> None:
    with pytest.raises(AppError) as error:
        NutritionCalculator.calculate(_rice(), Decimal("1"), "piece")
    assert error.value.code == "portion_conversion_unavailable"
