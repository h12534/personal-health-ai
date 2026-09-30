from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class DailyTargetRead(BaseModel):
    date: date
    phase: str
    bmr_kcal: int
    formula_tdee_kcal: int
    energy_target_kcal: int
    deficit_percent: Decimal
    protein_target_g: Decimal
    carbs_target_g: Decimal
    fat_target_g: Decimal
    carb_range_min_g: Decimal
    carb_range_max_g: Decimal
    fat_range_min_g: Decimal
    fat_range_max_g: Decimal
    fiber_target_g: Decimal
    water_target_ml: int
    source: str
    safety_notes: list[str]


class WeightTrendRead(BaseModel):
    as_of: date
    sample_days: int
    observations_14d: int
    average_7d_kg: Decimal | None
    previous_average_7d_kg: Decimal | None
    change_7d_kg: Decimal | None
    change_14d_kg: Decimal | None
    change_28d_kg: Decimal | None
    weekly_rate_kg: Decimal | None
    weekly_rate_percent: Decimal | None
    stability_kg: Decimal | None
    direction: Literal["down", "stable", "up", "insufficient_data"]
    plateau: bool
    plateau_eligible: bool
    note: str


class DietAdherenceRead(BaseModel):
    date_from: date
    date_to: date
    total_days: int
    logged_days: int
    complete_days: int
    calorie_adherent_days: int
    protein_adherent_days: int
    logging_rate: Decimal
    calorie_adherence_rate: Decimal
    protein_adherence_rate: Decimal
    overall_rate: Decimal


class EnergyModelRead(BaseModel):
    as_of: date
    formula_tdee: int
    observed_tdee: int | None
    blended_tdee: int
    confidence: Decimal
    sample_days: int
    completeness: Decimal
    method_version: str = "energy_v1"
    explanation: str


class MealTargetRange(BaseModel):
    calories_min: int
    calories_max: int
    protein_min_g: Decimal
    protein_max_g: Decimal
    carbs_hint_g: Decimal | None
    fat_hint_g: Decimal | None


class NextMealPlanRead(BaseModel):
    meal_type: str
    target: MealTargetRange
    remaining_calories: int
    remaining_protein_g: Decimal
    strategy: list[str]
    carb_guidance: str
    fat_guidance: str
    vegetable_guidance: str
    notes: list[str]
    over_target: bool
    today_training_status: Literal["completed", "in_progress", "planned", "rest_or_unplanned"]
    message: str


class DietAdjustmentRead(BaseModel):
    id: UUID
    user_id: UUID
    status: str
    previous_goal_id: UUID | None
    resulting_goal_id: UUID | None
    previous_calorie_target: int
    proposed_calorie_target: int
    previous_protein_target_g: Decimal
    proposed_protein_target_g: Decimal
    reason: str
    reason_code: str
    evidence_snapshot: dict[str, object]
    rule_version: str
    input_snapshot_hash: str
    source: str
    approved_by: str | None
    evaluate_after: date | None
    decided_at: datetime | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class AdjustmentDecision(BaseModel):
    idempotency_key: str = Field(min_length=8, max_length=128)


class HungerLogWrite(BaseModel):
    logged_at: datetime | None = None
    hunger_level: int = Field(ge=1, le=5)
    craving_level: int | None = Field(default=None, ge=1, le=5)
    context: str | None = Field(default=None, max_length=64)
    note: str | None = Field(default=None, max_length=1000)


class HungerLogRead(BaseModel):
    id: UUID
    user_id: UUID
    logged_at: datetime
    hunger_level: int
    craving_level: int | None
    context: str | None
    note: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class CanteenWrite(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    campus: str | None = Field(default=None, max_length=200)
    location: str | None = Field(default=None, max_length=300)
    note: str | None = Field(default=None, max_length=1000)


class CanteenRead(CanteenWrite):
    id: UUID
    user_id: UUID
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class StallWrite(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    cuisine: str | None = Field(default=None, max_length=100)
    floor: str | None = Field(default=None, max_length=64)
    location_note: str | None = Field(default=None, max_length=300)


class StallRead(StallWrite):
    id: UUID
    canteen_id: UUID
    is_active: bool

    model_config = {"from_attributes": True}


class DishWrite(BaseModel):
    food_item_id: UUID | None = None
    name: str = Field(min_length=1, max_length=200)
    calories: Decimal = Field(ge=0, le=5000)
    protein_g: Decimal = Field(ge=0, le=500)
    carbs_g: Decimal = Field(default=Decimal("0"), ge=0, le=1000)
    fat_g: Decimal = Field(default=Decimal("0"), ge=0, le=500)
    fiber_g: Decimal = Field(default=Decimal("0"), ge=0, le=100)
    portion_description: str | None = Field(default=None, max_length=200)
    average_weight_g: Decimal | None = Field(default=None, gt=0, le=10000)
    confidence: Decimal = Field(default=Decimal("0.5"), ge=0, le=1)
    favorite: bool = False
    source: str = Field(default="manual", max_length=32)
    tags: list[str] = Field(default_factory=list, max_length=30)


class DishRead(DishWrite):
    id: UUID
    stall_id: UUID
    is_available: bool
    times_logged: int
    last_seen: datetime | None

    model_config = {"from_attributes": True}


class StallDetailRead(StallRead):
    dishes: list[DishRead]


class CanteenDetailRead(CanteenRead):
    stalls: list[StallDetailRead]


class DishRecommendationRead(BaseModel):
    dish: DishRead
    match_score: Decimal
    reasons: list[str]


class MealRecommendationRead(BaseModel):
    source: Literal["saved_meal", "canteen_dish", "recent_food"]
    source_id: UUID
    name: str
    calories: Decimal
    protein_g: Decimal
    match_score: Decimal
    reasons: list[str]


class DietaryMemoryWrite(BaseModel):
    kind: str = Field(pattern="^(preference|dislike|allergy|routine|context)$")
    key: str | None = Field(default=None, min_length=1, max_length=120)
    value: str = Field(min_length=1, max_length=500)


class DietaryMemoryRead(BaseModel):
    id: UUID
    user_id: UUID
    kind: str
    key: str | None = Field(validation_alias="memory_key")
    value: str
    confidence: Decimal
    source: str
    created_at: datetime
    last_confirmed_at: datetime | None
    is_active: bool

    model_config = {"from_attributes": True}


class SavedMealItemWrite(BaseModel):
    food_id: UUID | None = None
    food_name: str = Field(min_length=1, max_length=200)
    amount: Decimal = Field(gt=0, le=10000)
    amount_unit: str = Field(min_length=1, max_length=32)
    weight_g: Decimal = Field(gt=0, le=10000)
    calories: Decimal = Field(ge=0, le=10000)
    protein: Decimal = Field(ge=0, le=1000)
    carbs: Decimal = Field(ge=0, le=2000)
    fat: Decimal = Field(ge=0, le=1000)
    fiber: Decimal = Field(default=Decimal("0"), ge=0, le=500)


class SavedMealWrite(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    meal_type: str = Field(default="meal", max_length=32)
    note: str | None = Field(default=None, max_length=1000)
    items: list[SavedMealItemWrite] = Field(min_length=1, max_length=50)


class SavedMealItemRead(SavedMealItemWrite):
    id: UUID
    food_name: str = Field(validation_alias="food_name_snapshot")

    model_config = {"from_attributes": True}


class SavedMealRead(BaseModel):
    id: UUID
    user_id: UUID
    name: str
    meal_type: str
    note: str | None
    items: list[SavedMealItemRead]
    created_at: datetime

    model_config = {"from_attributes": True}


class SavedMealLogWrite(BaseModel):
    eaten_at: datetime
    meal_type: str | None = Field(default=None, max_length=32)
    idempotency_key: str = Field(min_length=8, max_length=128)


class CoachChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    conversation_id: UUID | None = None
    context_mode: Literal["auto", "minimal"] = "auto"


class CoachSuggestedAction(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal[
        "open_next_meal",
        "open_canteen",
        "log_hunger",
        "review_adjustment",
        "log_weight",
        "none",
    ]
    label: str
    target_id: str | None


class CoachGeneratedReply(BaseModel):
    model_config = ConfigDict(extra="forbid")

    message: str
    suggested_actions: list[CoachSuggestedAction]
    safety_notice: str | None
    risk_level: Literal["normal", "caution", "urgent"]


class CoachChatResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    conversation_id: UUID
    intent: str
    message: str
    suggested_actions: list[CoachSuggestedAction]
    safety_notice: str | None
    provider: str
    model: str
    context_version: str
    used_context: list[str]
    safety_flags: list[str]
    references: list[str]


class WeeklyReviewRead(BaseModel):
    as_of: date
    headline: str
    average_calories: Decimal
    average_protein_g: Decimal
    average_fiber_g: Decimal
    high_calorie_meal_days: int
    observations: list[str]
    next_actions: list[str]
    trend: WeightTrendRead
    adherence: DietAdherenceRead
    adjustment: DietAdjustmentRead | None
