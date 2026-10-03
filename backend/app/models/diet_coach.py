from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
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


class DietAdjustment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "diet_adjustments"
    __table_args__ = (
        Index("ix_diet_adjustment_user_created", "user_id", "created_at"),
        UniqueConstraint("user_id", "idempotency_key", name="uq_adjustment_user_idempotency"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(String(24), default="pending", index=True)
    previous_goal_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("nutrition_goals.id", ondelete="SET NULL"), nullable=True
    )
    resulting_goal_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("nutrition_goals.id", ondelete="SET NULL"), nullable=True
    )
    previous_calorie_target: Mapped[int] = mapped_column(Integer, nullable=False)
    proposed_calorie_target: Mapped[int] = mapped_column(Integer, nullable=False)
    previous_protein_target_g: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    proposed_protein_target_g: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    reason_code: Mapped[str] = mapped_column(String(64), nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    evidence_snapshot: Mapped[dict[str, object]] = mapped_column(JSON_TYPE, default=dict)
    rule_version: Mapped[str] = mapped_column(String(32), default="diet_adjustment_v1")
    input_snapshot_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    source: Mapped[str] = mapped_column(String(32), default="rule_engine")
    approved_by: Mapped[str | None] = mapped_column(String(32), nullable=True)
    evaluate_after: Mapped[date | None] = mapped_column(Date, nullable=True)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)


class HungerLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "hunger_logs"
    __table_args__ = (Index("ix_hunger_user_logged", "user_id", "logged_at"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    logged_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    hunger_level: Mapped[int] = mapped_column(Integer, nullable=False)
    craving_level: Mapped[int | None] = mapped_column(Integer, nullable=True)
    context: Mapped[str | None] = mapped_column(String(64), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)


class Canteen(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "canteens"
    __table_args__ = (Index("ix_canteen_user_active", "user_id", "is_active"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    campus: Mapped[str | None] = mapped_column(String(200), nullable=True)
    location: Mapped[str | None] = mapped_column(String(300), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    stalls: Mapped[list["CanteenStall"]] = relationship(
        back_populates="canteen", cascade="all, delete-orphan", lazy="selectin"
    )


class CanteenStall(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "canteen_stalls"
    __table_args__ = (Index("ix_stall_canteen_active", "canteen_id", "is_active"),)

    canteen_id: Mapped[UUID] = mapped_column(ForeignKey("canteens.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    cuisine: Mapped[str | None] = mapped_column(String(100), nullable=True)
    floor: Mapped[str | None] = mapped_column(String(64), nullable=True)
    location_note: Mapped[str | None] = mapped_column(String(300), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    canteen: Mapped[Canteen] = relationship(back_populates="stalls")
    dishes: Mapped[list["CanteenDish"]] = relationship(
        back_populates="stall", cascade="all, delete-orphan", lazy="selectin"
    )


class CanteenDish(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "canteen_dishes"
    __table_args__ = (Index("ix_dish_stall_active", "stall_id", "is_available"),)

    stall_id: Mapped[UUID] = mapped_column(ForeignKey("canteen_stalls.id", ondelete="CASCADE"))
    food_item_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("food_items.id", ondelete="SET NULL"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    calories: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    protein_g: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    carbs_g: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=0)
    fat_g: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=0)
    fiber_g: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=0)
    portion_description: Mapped[str | None] = mapped_column(String(200), nullable=True)
    average_weight_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    confidence: Mapped[Decimal] = mapped_column(Numeric(4, 3), default=Decimal("0.5"))
    times_logged: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    favorite: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    source: Mapped[str] = mapped_column(String(32), default="manual", nullable=False)
    tags: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    is_available: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    stall: Mapped[CanteenStall] = relationship(back_populates="dishes")


class PersonalDietaryMemory(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "personal_dietary_memories"
    __table_args__ = (
        Index("ix_diet_memory_user_kind", "user_id", "kind"),
        UniqueConstraint("user_id", "kind", "normalized_value", name="uq_diet_memory_value"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(40), nullable=False)
    memory_key: Mapped[str | None] = mapped_column(String(120), nullable=True)
    value: Mapped[str] = mapped_column(String(500), nullable=False)
    normalized_value: Mapped[str] = mapped_column(String(500), nullable=False)
    confidence: Mapped[Decimal] = mapped_column(Numeric(4, 3), default=1)
    source: Mapped[str] = mapped_column(String(32), default="user")
    last_confirmed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class PersonalEnergyModel(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "personal_energy_models"
    __table_args__ = (
        Index("ix_energy_model_user_date", "user_id", "calculated_on"),
        UniqueConstraint("user_id", "calculated_on", name="uq_energy_model_user_date"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    calculated_on: Mapped[date] = mapped_column(Date, nullable=False)
    formula_tdee: Mapped[int] = mapped_column(Integer, nullable=False)
    observed_tdee: Mapped[int | None] = mapped_column(Integer, nullable=True)
    blended_tdee: Mapped[int] = mapped_column(Integer, nullable=False)
    confidence: Mapped[Decimal] = mapped_column(Numeric(4, 3), nullable=False)
    sample_days: Mapped[int] = mapped_column(Integer, nullable=False)
    completeness: Mapped[Decimal] = mapped_column(Numeric(4, 3), nullable=False)
    method_version: Mapped[str] = mapped_column(String(32), default="energy_v1")
    evidence_snapshot: Mapped[dict[str, object]] = mapped_column(JSON_TYPE, default=dict)


class SavedMeal(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "saved_meals"
    __table_args__ = (Index("ix_saved_meal_user_active", "user_id", "deleted_at"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    meal_type: Mapped[str] = mapped_column(String(32), default="meal")
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    items: Mapped[list["SavedMealItem"]] = relationship(
        back_populates="saved_meal", cascade="all, delete-orphan", lazy="selectin"
    )


class SavedMealItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "saved_meal_items"

    saved_meal_id: Mapped[UUID] = mapped_column(ForeignKey("saved_meals.id", ondelete="CASCADE"))
    food_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("food_items.id", ondelete="SET NULL"), nullable=True
    )
    food_name_snapshot: Mapped[str] = mapped_column(String(200), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    amount_unit: Mapped[str] = mapped_column(String(32), nullable=False)
    weight_g: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    calories: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    protein: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    carbs: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    fat: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    fiber: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    saved_meal: Mapped[SavedMeal] = relationship(back_populates="items")


class CoachConversation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "coach_conversations"
    __table_args__ = (Index("ix_coach_conversation_user_updated", "user_id", "updated_at"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    messages: Mapped[list["CoachMessage"]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan", lazy="selectin"
    )


class CoachMessage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "coach_messages"
    __table_args__ = (
        Index("ix_coach_message_conversation_created", "conversation_id", "created_at"),
    )

    conversation_id: Mapped[UUID] = mapped_column(
        ForeignKey("coach_conversations.id", ondelete="CASCADE")
    )
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    intent: Mapped[str | None] = mapped_column(String(48), nullable=True)
    provider: Mapped[str | None] = mapped_column(String(64), nullable=True)
    model: Mapped[str | None] = mapped_column(String(128), nullable=True)
    prompt_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    structured_payload: Mapped[dict[str, object] | None] = mapped_column(JSON_TYPE, nullable=True)
    conversation: Mapped[CoachConversation] = relationship(back_populates="messages")
