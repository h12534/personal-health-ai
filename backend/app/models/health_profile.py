from datetime import date
from decimal import Decimal
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import JSON, Boolean, Date, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class HealthProfile(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "health_profiles"

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    sex: Mapped[str | None] = mapped_column(String(32), nullable=True)
    height_cm: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    target_weight_kg: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    waist_cm: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    body_fat_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    resting_heart_rate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    activity_level: Mapped[str | None] = mapped_column(String(32), nullable=True)
    primary_goal: Mapped[str] = mapped_column(String(64), default="fat_loss_muscle_retention")
    training_experience: Mapped[str | None] = mapped_column(String(32), nullable=True)
    daily_exercise_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    school_life: Mapped[bool] = mapped_column(default=True)
    available_equipment: Mapped[list[str]] = mapped_column(JSON, default=list)
    dietary_environment: Mapped[list[str]] = mapped_column(
        JSON, default=lambda: ["school_canteen", "takeout", "convenience_store"]
    )
    food_preferences: Mapped[list[str]] = mapped_column(JSON, default=list)
    disliked_foods: Mapped[list[str]] = mapped_column(JSON, default=list)
    allergies: Mapped[list[str]] = mapped_column(JSON, default=list)
    known_health_risks: Mapped[list[str]] = mapped_column(JSON, default=list)
    medications: Mapped[list[str]] = mapped_column(JSON, default=list)
    doctor_advice: Mapped[str | None] = mapped_column(Text, nullable=True)
    timezone: Mapped[str] = mapped_column(String(64), default="Asia/Shanghai")
    allow_third_party_vision: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    retain_meal_images: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    current_goal_phase: Mapped[str] = mapped_column(String(32), default="fat_loss", nullable=False)
    allow_auto_diet_adjustment: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    adjustment_cooldown_days: Mapped[int] = mapped_column(Integer, default=14, nullable=False)

    user: Mapped["User"] = relationship(back_populates="health_profile")


if TYPE_CHECKING:
    from app.models.user import User
