from datetime import datetime
from decimal import Decimal
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, Index, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class MealLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "meal_logs"
    __table_args__ = (
        Index("ix_meal_user_eaten_at", "user_id", "eaten_at"),
        UniqueConstraint("user_id", "idempotency_key", name="uq_meal_user_idempotency"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    meal_type: Mapped[str] = mapped_column(String(32), index=True)
    eaten_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(String(32), default="manual")
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)
    total_calories: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    total_protein: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    total_carbs: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    total_fat: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    total_fiber: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=0)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    items: Mapped[list["MealItem"]] = relationship(
        back_populates="meal", cascade="all, delete-orphan", lazy="selectin"
    )


class MealItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "meal_items"
    __table_args__ = (
        Index("ix_meal_item_meal_active", "meal_id", "deleted_at"),
        UniqueConstraint("meal_id", "idempotency_key", name="uq_meal_item_idempotency"),
    )

    meal_id: Mapped[UUID] = mapped_column(ForeignKey("meal_logs.id", ondelete="CASCADE"))
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
    nutrition_source: Mapped[str] = mapped_column(String(64), nullable=False)
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    meal: Mapped[MealLog] = relationship(back_populates="items")
    food: Mapped["FoodItem | None"] = relationship(lazy="selectin")


if TYPE_CHECKING:
    from app.models.food import FoodItem
