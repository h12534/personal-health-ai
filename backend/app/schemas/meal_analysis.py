from datetime import datetime
from decimal import Decimal
from typing import Annotated, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.schemas.meal import MealType

VisionLabel = Annotated[str, Field(min_length=1, max_length=200)]
VisionWarning = Annotated[str, Field(min_length=1, max_length=500)]


class VisionWeightRange(BaseModel):
    model_config = ConfigDict(extra="forbid")

    min_g: Decimal = Field(gt=0, le=5000)
    max_g: Decimal = Field(gt=0, le=5000)

    @model_validator(mode="after")
    def ordered(self) -> Self:
        if self.min_g > self.max_g:
            raise ValueError("min_g must not exceed max_g")
        return self


class VisionFoodDetection(BaseModel):
    model_config = ConfigDict(extra="forbid")

    detected_name: str = Field(min_length=1, max_length=200)
    aliases: list[VisionLabel] = Field(max_length=10)
    estimated_weight_g: Decimal = Field(gt=0, le=5000)
    weight_range: VisionWeightRange
    portion_description: str | None = Field(max_length=300)
    cooking_method: str | None = Field(max_length=100)
    recognition_confidence: Decimal = Field(ge=0, le=1)
    portion_confidence: Decimal = Field(ge=0, le=1)
    visible_components: list[VisionLabel] = Field(max_length=20)
    possible_hidden_ingredients: list[VisionLabel] = Field(max_length=20)
    possible_oil_weight: VisionWeightRange | None

    @model_validator(mode="after")
    def estimate_inside_range(self) -> Self:
        if not self.weight_range.min_g <= self.estimated_weight_g <= self.weight_range.max_g:
            raise ValueError("estimated_weight_g must fall inside weight_range")
        return self


class VisionMealResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    no_food_detected: bool
    foods: list[VisionFoodDetection] = Field(max_length=30)
    overall_confidence: Decimal = Field(ge=0, le=1)
    warnings: list[VisionWarning] = Field(max_length=20)

    @model_validator(mode="after")
    def food_state_consistent(self) -> Self:
        if self.no_food_detected and self.foods:
            raise ValueError("foods must be empty when no_food_detected is true")
        if not self.no_food_detected and not self.foods:
            raise ValueError("foods cannot be empty unless no_food_detected is true")
        return self


class MealAnalysisItemPatch(BaseModel):
    matched_food_id: UUID | None = None
    detected_name: str | None = Field(default=None, min_length=1, max_length=200)
    estimated_weight_g: Decimal | None = Field(default=None, gt=0, le=5000)
    min_weight_g: Decimal | None = Field(default=None, gt=0, le=5000)
    max_weight_g: Decimal | None = Field(default=None, gt=0, le=5000)
    portion_description: str | None = Field(default=None, max_length=300)
    cooking_method: str | None = Field(default=None, max_length=100)


class MealAnalysisItemCreate(BaseModel):
    food_id: UUID
    detected_name: str | None = Field(default=None, min_length=1, max_length=200)
    estimated_weight_g: Decimal = Field(gt=0, le=5000)
    min_weight_g: Decimal | None = Field(default=None, gt=0, le=5000)
    max_weight_g: Decimal | None = Field(default=None, gt=0, le=5000)
    portion_description: str | None = Field(default=None, max_length=300)


class MealAnalysisConfirmItem(BaseModel):
    analysis_item_id: UUID
    food_id: UUID
    weight_g: Decimal = Field(gt=0, le=5000)


class MealAnalysisConfirm(BaseModel):
    meal_type: MealType
    eaten_at: datetime
    note: str | None = Field(default=None, max_length=4000)
    items: list[MealAnalysisConfirmItem] | None = Field(default=None, min_length=1, max_length=50)

    @field_validator("eaten_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("eaten_at must include a timezone offset")
        return value


class MealAnalysisItemRead(BaseModel):
    id: UUID
    position: int
    detected_name: str
    matched_food_id: UUID | None
    matched_food_name: str | None
    match_type: str
    match_confidence: Decimal
    recognition_confidence: Decimal
    portion_confidence: Decimal
    confidence_label: str
    estimated_weight_g: Decimal
    min_weight_g: Decimal
    max_weight_g: Decimal
    portion_description: str | None
    cooking_method: str | None
    visible_components: list[str]
    possible_hidden_ingredients: list[str]
    is_hidden_ingredient: bool
    user_modified: bool
    calories: Decimal
    protein: Decimal
    carbs: Decimal
    fat: Decimal
    fiber: Decimal
    min_calories: Decimal
    max_calories: Decimal


class MealAnalysisTotals(BaseModel):
    calories: Decimal
    min_calories: Decimal
    max_calories: Decimal
    protein: Decimal
    carbs: Decimal
    fat: Decimal
    fiber: Decimal


class MealAnalysisRead(BaseModel):
    id: UUID
    status: str
    meal_type: str | None
    eaten_at: datetime | None
    note: str | None
    location_context: str | None
    provider: str
    model: str
    prompt_version: str
    overall_confidence: Decimal | None
    confidence_label: str | None
    warnings: list[str]
    error_code: str | None
    error_message: str | None
    reanalysis_count: int
    expires_at: datetime
    confirmed_meal_id: UUID | None
    items: list[MealAnalysisItemRead]
    totals: MealAnalysisTotals
    created_at: datetime
    updated_at: datetime
