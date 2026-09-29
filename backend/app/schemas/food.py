from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class FoodBase(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False)

    name: str = Field(min_length=1, max_length=200)
    brand: str | None = Field(default=None, max_length=200)
    category: str = Field(default="other", min_length=1, max_length=64, pattern=r"^[a-z0-9_]+$")
    serving_description: str | None = Field(default=None, max_length=200)
    serving_unit: str | None = Field(default=None, max_length=32)
    serving_weight_g: Decimal | None = Field(default=None, gt=0, le=100000, decimal_places=3)
    calories_per_100g: Decimal = Field(ge=0, le=1000, decimal_places=3)
    protein_per_100g: Decimal = Field(ge=0, le=100, decimal_places=3)
    carbs_per_100g: Decimal = Field(ge=0, le=100, decimal_places=3)
    fat_per_100g: Decimal = Field(ge=0, le=100, decimal_places=3)
    fiber_per_100g: Decimal = Field(default=Decimal("0"), ge=0, le=100, decimal_places=3)
    sugar_per_100g: Decimal | None = Field(default=None, ge=0, le=100, decimal_places=3)
    sodium_mg_per_100g: Decimal | None = Field(default=None, ge=0, le=100000)
    potassium_mg_per_100g: Decimal | None = Field(default=None, ge=0, le=100000)
    calcium_mg_per_100g: Decimal | None = Field(default=None, ge=0, le=100000)
    iron_mg_per_100g: Decimal | None = Field(default=None, ge=0, le=10000)

    @model_validator(mode="after")
    def serving_is_complete(self) -> "FoodBase":
        if (self.serving_unit is None) != (self.serving_weight_g is None):
            raise ValueError("serving_unit and serving_weight_g must be provided together")
        return self


class FoodCreate(FoodBase):
    aliases: list[str] = Field(default_factory=list, max_length=30)


class FoodUpdate(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False)

    name: str | None = Field(default=None, min_length=1, max_length=200)
    brand: str | None = Field(default=None, max_length=200)
    category: str | None = Field(default=None, max_length=64, pattern=r"^[a-z0-9_]+$")
    serving_description: str | None = Field(default=None, max_length=200)
    serving_unit: str | None = Field(default=None, max_length=32)
    serving_weight_g: Decimal | None = Field(default=None, gt=0, le=100000, decimal_places=3)
    calories_per_100g: Decimal | None = Field(default=None, ge=0, le=1000)
    protein_per_100g: Decimal | None = Field(default=None, ge=0, le=100)
    carbs_per_100g: Decimal | None = Field(default=None, ge=0, le=100)
    fat_per_100g: Decimal | None = Field(default=None, ge=0, le=100)
    fiber_per_100g: Decimal | None = Field(default=None, ge=0, le=100)
    sugar_per_100g: Decimal | None = Field(default=None, ge=0, le=100)
    sodium_mg_per_100g: Decimal | None = Field(default=None, ge=0, le=100000)
    potassium_mg_per_100g: Decimal | None = Field(default=None, ge=0, le=100000)
    calcium_mg_per_100g: Decimal | None = Field(default=None, ge=0, le=100000)
    iron_mg_per_100g: Decimal | None = Field(default=None, ge=0, le=10000)
    aliases: list[str] | None = Field(default=None, max_length=30)


class FoodRead(FoodBase):
    id: UUID
    source: str
    source_id: str | None
    data_source_name: str | None
    data_source_url: str | None
    is_custom: bool
    is_favorite: bool = False
    aliases: list[str] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class FavoriteRead(BaseModel):
    food: FoodRead
    favorited_at: datetime
