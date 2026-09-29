from datetime import datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from sqlalchemy import (
    JSON,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin

JSON_TYPE = JSON().with_variant(JSONB(), "postgresql")


class MealImage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "meal_images"
    __table_args__ = (Index("ix_meal_image_user_created", "user_id", "created_at"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    object_key: Mapped[str] = mapped_column(String(500), unique=True, nullable=False)
    content_type: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    width: Mapped[int] = mapped_column(Integer, nullable=False)
    height: Mapped[int] = mapped_column(Integer, nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    retention_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class MealAnalysisSession(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "meal_analysis_sessions"
    __table_args__ = (
        Index("ix_analysis_user_created", "user_id", "created_at"),
        Index("ix_analysis_status_expires", "status", "expires_at"),
        Index("ix_analysis_image", "image_id"),
        UniqueConstraint("user_id", "idempotency_key", name="uq_analysis_user_idempotency"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    image_id: Mapped[UUID] = mapped_column(ForeignKey("meal_images.id", ondelete="RESTRICT"))
    confirmed_meal_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("meal_logs.id", ondelete="SET NULL"), nullable=True
    )
    status: Mapped[str] = mapped_column(String(32), default="pending", nullable=False)
    provider: Mapped[str] = mapped_column(String(64), nullable=False)
    model: Mapped[str] = mapped_column(String(128), nullable=False)
    prompt_version: Mapped[str] = mapped_column(String(64), nullable=False)
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)
    confirm_idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)
    location_context: Mapped[str | None] = mapped_column(String(100), nullable=True)
    meal_type: Mapped[str | None] = mapped_column(String(32), nullable=True)
    eaten_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    overall_confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 4), nullable=True)
    warnings: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list, nullable=False)
    raw_provider_response: Mapped[dict[str, Any] | None] = mapped_column(JSON_TYPE, nullable=True)
    attempt_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    reanalysis_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    error_code: Mapped[str | None] = mapped_column(String(100), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    image: Mapped[MealImage] = relationship(lazy="selectin")
    items: Mapped[list["MealAnalysisItem"]] = relationship(
        back_populates="session",
        cascade="all, delete-orphan",
        lazy="selectin",
        order_by="MealAnalysisItem.position",
    )


class MealAnalysisItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "meal_analysis_items"
    __table_args__ = (Index("ix_analysis_item_session_active", "session_id", "deleted_at"),)

    session_id: Mapped[UUID] = mapped_column(
        ForeignKey("meal_analysis_sessions.id", ondelete="CASCADE")
    )
    matched_food_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("food_items.id", ondelete="SET NULL"), nullable=True
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    detected_name: Mapped[str] = mapped_column(String(200), nullable=False)
    match_type: Mapped[str] = mapped_column(String(32), nullable=False)
    match_confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4), default=0)
    recognition_confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4), nullable=False)
    portion_confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4), nullable=False)
    estimated_weight_g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    min_weight_g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    max_weight_g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    original_ai_weight_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    portion_description: Mapped[str | None] = mapped_column(String(300), nullable=True)
    cooking_method: Mapped[str | None] = mapped_column(String(100), nullable=True)
    visible_components: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list, nullable=False)
    possible_hidden_ingredients: Mapped[list[str]] = mapped_column(
        JSON_TYPE, default=list, nullable=False
    )
    is_hidden_ingredient: Mapped[bool] = mapped_column(default=False, nullable=False)
    user_modified: Mapped[bool] = mapped_column(default=False, nullable=False)
    calories: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    protein: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    carbs: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    fat: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    fiber: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    min_calories: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    max_calories: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    min_protein: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    max_protein: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    min_carbs: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    max_carbs: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    min_fat: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    max_fat: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    min_fiber: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    max_fiber: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    session: Mapped[MealAnalysisSession] = relationship(back_populates="items")
    matched_food: Mapped["FoodItem | None"] = relationship(lazy="selectin")


class PersonalFoodMemory(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "personal_food_memories"
    __table_args__ = (
        Index("ix_food_memory_user_label", "user_id", "normalized_detected_label"),
        Index(
            "uq_food_memory_context",
            "user_id",
            "normalized_detected_label",
            "confirmed_food_id",
            "location_context",
            unique=True,
        ),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    normalized_detected_label: Mapped[str] = mapped_column(String(200), nullable=False)
    confirmed_food_id: Mapped[UUID] = mapped_column(ForeignKey("food_items.id", ondelete="CASCADE"))
    location_context: Mapped[str] = mapped_column(String(100), default="unspecified")
    average_ai_weight_g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    average_confirmed_weight_g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    sample_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4), default=1, nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    confirmed_food: Mapped["FoodItem"] = relationship(lazy="selectin")


class AIUsageLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "ai_usage_logs"
    __table_args__ = (Index("ix_ai_usage_user_created", "user_id", "created_at"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    analysis_session_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("meal_analysis_sessions.id", ondelete="SET NULL"), nullable=True
    )
    provider: Mapped[str] = mapped_column(String(64), nullable=False)
    model: Mapped[str] = mapped_column(String(128), nullable=False)
    task: Mapped[str] = mapped_column(String(64), default="meal_vision", nullable=False)
    input_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    output_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    image_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    latency_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    estimated_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 6), nullable=True)
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    error_code: Mapped[str | None] = mapped_column(String(100), nullable=True)


from app.models.food import FoodItem  # noqa: E402
