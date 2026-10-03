from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    JSON,
    Boolean,
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


class Exercise(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "exercise_library"
    __table_args__ = (UniqueConstraint("normalized_name"),)

    name: Mapped[str] = mapped_column(String(160), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    category: Mapped[str] = mapped_column(String(64), nullable=False)
    movement_pattern: Mapped[str] = mapped_column(String(32), index=True)
    primary_muscles: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    secondary_muscles: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    equipment: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    difficulty: Mapped[str] = mapped_column(String(24), default="beginner")
    instructions: Mapped[str] = mapped_column(Text, nullable=False)
    setup_instructions: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    execution_cues: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    common_mistakes: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    safety_notes: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    video_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    unilateral: Mapped[bool] = mapped_column(Boolean, default=False)
    bodyweight: Mapped[bool] = mapped_column(Boolean, default=False)
    compound: Mapped[bool] = mapped_column(Boolean, default=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)


class TrainingPlan(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "training_plans"
    __table_args__ = (Index("ix_training_plan_user_active", "user_id", "active"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    goal: Mapped[str] = mapped_column(String(64), default="fat_loss_muscle_retention")
    difficulty: Mapped[str] = mapped_column(String(24), default="beginner")
    weeks: Mapped[int] = mapped_column(Integer, default=8)
    sessions_per_week: Mapped[int] = mapped_column(Integer, default=3)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    days: Mapped[list["TrainingDay"]] = relationship(
        back_populates="plan", cascade="all, delete-orphan", lazy="selectin"
    )


class TrainingDay(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "training_days"
    __table_args__ = (
        UniqueConstraint("plan_id", "day_number", name="uq_training_day_number"),
        UniqueConstraint("plan_id", "order_index", name="uq_training_day_order"),
    )

    plan_id: Mapped[UUID] = mapped_column(ForeignKey("training_plans.id", ondelete="CASCADE"))
    day_number: Mapped[int] = mapped_column(Integer, nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    focus: Mapped[str] = mapped_column(String(120), nullable=False)
    estimated_duration_min: Mapped[int] = mapped_column(Integer, default=60)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)

    plan: Mapped[TrainingPlan] = relationship(back_populates="days")
    exercises: Mapped[list["TrainingExercise"]] = relationship(
        back_populates="training_day", cascade="all, delete-orphan", lazy="selectin"
    )


class TrainingExercise(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "training_exercises"
    __table_args__ = (
        UniqueConstraint("training_day_id", "order_index", name="uq_training_exercise_order"),
    )

    training_day_id: Mapped[UUID] = mapped_column(
        ForeignKey("training_days.id", ondelete="CASCADE")
    )
    exercise_id: Mapped[UUID] = mapped_column(
        ForeignKey("exercise_library.id", ondelete="RESTRICT")
    )
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    target_sets: Mapped[int] = mapped_column(Integer, default=3)
    target_rep_min: Mapped[int] = mapped_column(Integer, default=8)
    target_rep_max: Mapped[int] = mapped_column(Integer, default=12)
    target_weight_kg: Mapped[Decimal | None] = mapped_column(Numeric(8, 2), nullable=True)
    target_rpe: Mapped[Decimal | None] = mapped_column(Numeric(3, 1), nullable=True)
    target_rir: Mapped[Decimal | None] = mapped_column(Numeric(3, 1), default=2)
    rest_seconds: Mapped[int] = mapped_column(Integer, default=120)
    tempo: Mapped[str | None] = mapped_column(String(32), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    progression_type: Mapped[str] = mapped_column(String(32), default="double_progression")

    training_day: Mapped[TrainingDay] = relationship(back_populates="exercises")
    exercise: Mapped[Exercise] = relationship(lazy="selectin")


class WorkoutSession(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "workout_sessions"
    __table_args__ = (
        Index("ix_workout_user_started", "user_id", "started_at"),
        UniqueConstraint("user_id", "idempotency_key", name="uq_workout_user_idempotency"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    training_day_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("training_days.id", ondelete="SET NULL"), nullable=True
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[str] = mapped_column(String(24), default="in_progress")
    session_rpe: Mapped[Decimal | None] = mapped_column(Numeric(3, 1), nullable=True)
    energy_level: Mapped[int | None] = mapped_column(Integer, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(String(32), default="manual")
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)

    sets: Mapped[list["WorkoutSet"]] = relationship(
        back_populates="session", cascade="all, delete-orphan", lazy="selectin"
    )


class WorkoutSet(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "workout_sets"
    __table_args__ = (
        Index("ix_workout_set_session_exercise", "session_id", "exercise_id"),
        UniqueConstraint("session_id", "idempotency_key", name="uq_workout_set_idempotency"),
    )

    session_id: Mapped[UUID] = mapped_column(ForeignKey("workout_sessions.id", ondelete="CASCADE"))
    exercise_id: Mapped[UUID] = mapped_column(
        ForeignKey("exercise_library.id", ondelete="RESTRICT")
    )
    set_number: Mapped[int] = mapped_column(Integer, nullable=False)
    set_type: Mapped[str] = mapped_column(String(24), default="working")
    weight_kg: Mapped[Decimal] = mapped_column(Numeric(8, 2), default=0)
    reps: Mapped[int] = mapped_column(Integer, default=0)
    rpe: Mapped[Decimal | None] = mapped_column(Numeric(3, 1), nullable=True)
    rir: Mapped[Decimal | None] = mapped_column(Numeric(3, 1), nullable=True)
    completed: Mapped[bool] = mapped_column(Boolean, default=True)
    rest_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)

    session: Mapped[WorkoutSession] = relationship(back_populates="sets")
    exercise: Mapped[Exercise] = relationship(lazy="selectin")


class ExercisePR(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "exercise_prs"
    __table_args__ = (
        Index("ix_exercise_pr_user_exercise", "user_id", "exercise_id"),
        UniqueConstraint("user_id", "exercise_id", "pr_type", name="uq_exercise_pr_user_type"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    exercise_id: Mapped[UUID] = mapped_column(ForeignKey("exercise_library.id", ondelete="CASCADE"))
    workout_set_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("workout_sets.id", ondelete="SET NULL"), nullable=True
    )
    pr_type: Mapped[str] = mapped_column(String(24), nullable=False)
    value: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    achieved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    confidence: Mapped[str] = mapped_column(String(16), default="normal")


class PainLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "pain_logs"
    __table_args__ = (Index("ix_pain_user_created", "user_id", "created_at"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    workout_session_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("workout_sessions.id", ondelete="SET NULL"), nullable=True
    )
    exercise_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("exercise_library.id", ondelete="SET NULL"), nullable=True
    )
    body_area: Mapped[str] = mapped_column(String(64), nullable=False)
    severity: Mapped[int] = mapped_column(Integer, nullable=False)
    symptoms: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    acute: Mapped[bool] = mapped_column(Boolean, default=False)


class TrainingAdjustment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "training_adjustments"
    __table_args__ = (
        Index("ix_training_adjustment_user_status", "user_id", "status"),
        UniqueConstraint("user_id", "idempotency_key", name="uq_training_adjustment_key"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    training_exercise_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("training_exercises.id", ondelete="SET NULL"), nullable=True
    )
    adjustment_type: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(24), default="suggested")
    previous_value: Mapped[dict[str, object]] = mapped_column(JSON_TYPE, default=dict)
    proposed_value: Mapped[dict[str, object]] = mapped_column(JSON_TYPE, default=dict)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    evidence_snapshot: Mapped[dict[str, object]] = mapped_column(JSON_TYPE, default=dict)
    rule_version: Mapped[str] = mapped_column(String(32), default="progression_v1")
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)
    applied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
