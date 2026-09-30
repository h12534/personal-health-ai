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
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class ActivityLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "activity_logs"
    __table_args__ = (
        Index("ix_activity_user_date", "user_id", "activity_date"),
        UniqueConstraint("user_id", "source", "source_record_id", name="uq_activity_source"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    activity_date: Mapped[date] = mapped_column(Date, nullable=False)
    activity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    distance_km: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    active_energy_kcal: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    average_heart_rate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    rpe: Mapped[Decimal | None] = mapped_column(Numeric(3, 1), nullable=True)
    source: Mapped[str] = mapped_column(String(32), default="manual")
    source_record_id: Mapped[str | None] = mapped_column(String(200), nullable=True)


class StepLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "step_logs"
    __table_args__ = (
        UniqueConstraint("user_id", "step_date", "source", name="uq_step_daily_source"),
        UniqueConstraint("user_id", "source", "source_record_id", name="uq_step_source_record"),
        Index("ix_step_user_date", "user_id", "step_date"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    step_date: Mapped[date] = mapped_column(Date, nullable=False)
    steps: Mapped[int | None] = mapped_column(Integer, nullable=True)
    distance_km: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    active_energy_kcal: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    resting_heart_rate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source: Mapped[str] = mapped_column(String(32), default="manual")
    source_record_id: Mapped[str | None] = mapped_column(String(200), nullable=True)


class SleepLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "sleep_logs"
    __table_args__ = (
        Index("ix_sleep_user_start", "user_id", "sleep_start"),
        UniqueConstraint("user_id", "source", "source_record_id", name="uq_sleep_source_record"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    sleep_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    sleep_end: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    duration_min: Mapped[int] = mapped_column(Integer, nullable=False)
    source: Mapped[str] = mapped_column(String(32), default="manual")
    sleep_stages: Mapped[list[dict[str, object]]] = mapped_column(JSON, default=list)
    quality: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source_record_id: Mapped[str | None] = mapped_column(String(200), nullable=True)


class HealthSyncState(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "health_sync_state"
    __table_args__ = (
        UniqueConstraint("user_id", "provider", "data_type", name="uq_health_sync_type"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    data_type: Mapped[str] = mapped_column(String(40), nullable=False)
    last_sync_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    cursor: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(24), default="never")
    error_summary: Mapped[str | None] = mapped_column(String(500), nullable=True)


class HealthPermissionState(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "health_permission_state"
    __table_args__ = (
        UniqueConstraint("user_id", "provider", "data_type", name="uq_health_permission_type"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    data_type: Mapped[str] = mapped_column(String(40), nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    authorization_status: Mapped[str] = mapped_column(String(24), default="not_requested")
    requested_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class RecoverySnapshot(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "recovery_snapshots"
    __table_args__ = (
        UniqueConstraint("user_id", "snapshot_date", name="uq_recovery_user_date"),
        Index("ix_recovery_user_date", "user_id", "snapshot_date"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    snapshot_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False)
    sleep_duration_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    subjective_fatigue: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_session_rpe: Mapped[Decimal | None] = mapped_column(Numeric(3, 1), nullable=True)
    resting_heart_rate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    resting_heart_rate_baseline: Mapped[Decimal | None] = mapped_column(
        Numeric(6, 2), nullable=True
    )
    pain_severity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    recent_training_count: Mapped[int] = mapped_column(Integer, default=0)
    reasons: Mapped[list[str]] = mapped_column(JSON, default=list)
    evidence_snapshot: Mapped[dict[str, object]] = mapped_column(JSON, default=dict)
    rule_version: Mapped[str] = mapped_column(String(32), default="recovery_v1")
