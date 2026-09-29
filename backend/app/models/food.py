from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class FoodItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "food_items"
    __table_args__ = (
        CheckConstraint(
            "(is_custom = false) OR (owner_user_id IS NOT NULL)",
            name="ck_custom_food_has_owner",
        ),
        UniqueConstraint("source", "source_id", name="uq_food_source_id"),
        Index("ix_food_normalized_name", "normalized_name"),
        Index("ix_food_owner_active", "owner_user_id", "is_active"),
    )

    owner_user_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(200), nullable=False)
    brand: Mapped[str | None] = mapped_column(String(200), nullable=True)
    category: Mapped[str] = mapped_column(String(64), default="other", index=True)
    source: Mapped[str] = mapped_column(String(64), default="user")
    source_id: Mapped[str | None] = mapped_column(String(200), nullable=True)
    data_source_name: Mapped[str | None] = mapped_column(String(300), nullable=True)
    data_source_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_custom: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    serving_description: Mapped[str | None] = mapped_column(String(200), nullable=True)
    serving_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    serving_weight_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    calories_per_100g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    protein_per_100g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    carbs_per_100g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    fat_per_100g: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    fiber_per_100g: Mapped[Decimal] = mapped_column(Numeric(10, 3), default=0)
    sugar_per_100g: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    sodium_mg_per_100g: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    potassium_mg_per_100g: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    calcium_mg_per_100g: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    iron_mg_per_100g: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    aliases: Mapped[list["FoodAlias"]] = relationship(
        back_populates="food", cascade="all, delete-orphan", lazy="selectin"
    )
    favorites: Mapped[list["FoodFavorite"]] = relationship(back_populates="food")


class FoodAlias(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "food_aliases"
    __table_args__ = (
        UniqueConstraint("food_id", "normalized_alias", name="uq_food_alias_normalized"),
        Index("ix_food_alias_normalized", "normalized_alias"),
    )

    food_id: Mapped[UUID] = mapped_column(ForeignKey("food_items.id", ondelete="CASCADE"))
    alias: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_alias: Mapped[str] = mapped_column(String(200), nullable=False)
    language: Mapped[str] = mapped_column(String(16), default="zh-CN")

    food: Mapped[FoodItem] = relationship(back_populates="aliases")


class FoodFavorite(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "food_favorites"
    __table_args__ = (
        UniqueConstraint("user_id", "food_id", name="uq_favorite_user_food"),
        Index("ix_favorite_user_created", "user_id", "created_at"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    food_id: Mapped[UUID] = mapped_column(ForeignKey("food_items.id", ondelete="CASCADE"))

    food: Mapped[FoodItem] = relationship(back_populates="favorites", lazy="selectin")
