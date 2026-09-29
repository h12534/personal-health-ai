from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class NutritionTotals(BaseModel):
    calories: Decimal = Decimal("0")
    protein: Decimal = Decimal("0")
    carbs: Decimal = Decimal("0")
    fat: Decimal = Decimal("0")
    fiber: Decimal = Decimal("0")


class DailyNutrition(BaseModel):
    date: date
    totals: NutritionTotals
    meals: dict[str, NutritionTotals]
    meal_counts: dict[str, int]
    meal_count: int


class NutritionRangeDay(BaseModel):
    date: date
    totals: NutritionTotals
    meal_count: int


class NutritionGoalWrite(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False)

    effective_from: date
    effective_to: date | None = None
    calorie_target: int = Field(ge=1200, le=10000)
    protein_target_g: Decimal = Field(ge=30, le=500)
    carbs_target_g: Decimal | None = Field(default=None, ge=20, le=1500)
    fat_target_g: Decimal | None = Field(default=None, ge=20, le=500)
    fiber_target_g: Decimal = Field(default=Decimal("25"), ge=10, le=100)
    water_target_ml: int = Field(default=2500, ge=500, le=10000)
    source: str = Field(default="manual", max_length=32)
    reason: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def validate_dates(self) -> "NutritionGoalWrite":
        if self.effective_to is not None and self.effective_to < self.effective_from:
            raise ValueError("effective_to cannot be before effective_from")
        return self


class NutritionGoalUpdate(BaseModel):
    effective_to: date | None = None
    calorie_target: int | None = Field(default=None, ge=1200, le=10000)
    protein_target_g: Decimal | None = Field(default=None, ge=30, le=500)
    carbs_target_g: Decimal | None = Field(default=None, ge=20, le=1500)
    fat_target_g: Decimal | None = Field(default=None, ge=20, le=500)
    fiber_target_g: Decimal | None = Field(default=None, ge=10, le=100)
    water_target_ml: int | None = Field(default=None, ge=500, le=10000)
    reason: str | None = Field(default=None, max_length=2000)


class NutritionGoalRead(NutritionGoalWrite):
    id: UUID
    user_id: UUID
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
