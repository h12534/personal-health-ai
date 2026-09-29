from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Date, DateTime, ForeignKey, Index, Integer, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class NutritionGoal(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "nutrition_goals"
    __table_args__ = (Index("ix_goal_user_effective", "user_id", "effective_from"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    effective_from: Mapped[date] = mapped_column(Date, nullable=False)
    effective_to: Mapped[date | None] = mapped_column(Date, nullable=True)
    calorie_target: Mapped[int] = mapped_column(Integer, nullable=False)
    protein_target_g: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    carbs_target_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    fat_target_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    fiber_target_g: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    water_target_ml: Mapped[int] = mapped_column(Integer, nullable=False)
    source: Mapped[str] = mapped_column(String(32), default="manual")
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
