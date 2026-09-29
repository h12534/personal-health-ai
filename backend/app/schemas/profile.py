from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field


class HealthProfileWrite(BaseModel):
    birth_date: date | None = None
    sex: str | None = Field(default=None, max_length=32)
    height_cm: Decimal | None = Field(default=None, ge=80, le=250)
    target_weight_kg: Decimal | None = Field(default=None, ge=30, le=400)
    waist_cm: Decimal | None = Field(default=None, ge=30, le=300)
    body_fat_percent: Decimal | None = Field(default=None, ge=2, le=75)
    resting_heart_rate: int | None = Field(default=None, ge=25, le=240)
    activity_level: str | None = Field(default=None, max_length=32)
    primary_goal: str = Field(default="fat_loss_muscle_retention", max_length=64)
    training_experience: str | None = Field(default=None, max_length=32)
    daily_exercise_minutes: int | None = Field(default=None, ge=0, le=300)
    school_life: bool = True
    available_equipment: list[str] = Field(default_factory=list, max_length=50)
    dietary_environment: list[str] = Field(
        default_factory=lambda: ["school_canteen", "takeout", "convenience_store"],
        max_length=20,
    )
    food_preferences: list[str] = Field(default_factory=list, max_length=100)
    disliked_foods: list[str] = Field(default_factory=list, max_length=100)
    allergies: list[str] = Field(default_factory=list, max_length=100)
    known_health_risks: list[str] = Field(default_factory=list, max_length=100)
    medications: list[str] = Field(default_factory=list, max_length=100)
    doctor_advice: str | None = Field(default=None, max_length=4000)
    timezone: str = Field(default="Asia/Shanghai", max_length=64)
    allow_third_party_vision: bool = False
    retain_meal_images: bool = False
    current_goal_phase: str = Field(default="fat_loss", max_length=32)
    allow_auto_diet_adjustment: bool = False
    adjustment_cooldown_days: int = Field(default=14, ge=7, le=90)


class HealthProfileRead(HealthProfileWrite):
    id: UUID
    user_id: UUID
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class VisionPrivacyWrite(BaseModel):
    allow_third_party_vision: bool
    retain_meal_images: bool


class VisionPrivacyRead(VisionPrivacyWrite):
    pass
