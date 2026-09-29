from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

MealType = Literal["breakfast", "lunch", "dinner", "snack"]
AmountUnit = Literal["g", "ml", "serving", "piece", "bowl", "cup", "custom"]


class MealCreate(BaseModel):
    meal_type: MealType
    eaten_at: datetime
    note: str | None = Field(default=None, max_length=2000)
    source: str = Field(default="manual", max_length=32)

    @field_validator("eaten_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("eaten_at must include a timezone offset")
        return value


class MealUpdate(BaseModel):
    meal_type: MealType | None = None
    eaten_at: datetime | None = None
    note: str | None = Field(default=None, max_length=2000)

    @field_validator("eaten_at")
    @classmethod
    def require_timezone(cls, value: datetime | None) -> datetime | None:
        if value is not None and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError("eaten_at must include a timezone offset")
        return value


class MealItemWrite(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False)

    food_id: UUID
    amount: Decimal = Field(gt=0, le=100000, decimal_places=3)
    amount_unit: AmountUnit


class MealItemUpdate(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False)

    food_id: UUID | None = None
    amount: Decimal | None = Field(default=None, gt=0, le=100000, decimal_places=3)
    amount_unit: AmountUnit | None = None


class MealItemRead(BaseModel):
    id: UUID
    food_id: UUID | None
    food_name_snapshot: str
    amount: Decimal
    amount_unit: str
    weight_g: Decimal
    calories: Decimal
    protein: Decimal
    carbs: Decimal
    fat: Decimal
    fiber: Decimal
    nutrition_source: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class MealRead(BaseModel):
    id: UUID
    meal_type: str
    eaten_at: datetime
    note: str | None
    source: str
    total_calories: Decimal
    total_protein: Decimal
    total_carbs: Decimal
    total_fat: Decimal
    total_fiber: Decimal
    items: list[MealItemRead]
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
