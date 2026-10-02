from datetime import date, datetime, time
from uuid import UUID

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    Time,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class DailyTask(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "daily_tasks"
    __table_args__ = (
        UniqueConstraint("user_id", "task_date", "dedup_key", name="uq_daily_task_dedup"),
        Index("ix_daily_task_user_date_status", "user_id", "task_date", "status"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    task_date: Mapped[date] = mapped_column(Date, nullable=False)
    task_type: Mapped[str] = mapped_column(String(40), nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(24), default="pending", nullable=False)
    priority: Mapped[int] = mapped_column(Integer, default=50, nullable=False)
    scheduled_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    source: Mapped[str] = mapped_column(String(40), default="daily_engine", nullable=False)
    source_entity_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    reminder_policy: Mapped[dict[str, object]] = mapped_column(JSON, default=dict)
    dedup_key: Mapped[str] = mapped_column(String(240), nullable=False)


class ReminderPreference(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "reminder_preferences"
    __table_args__ = (UniqueConstraint("user_id", name="uq_reminder_preference_user"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    mode: Mapped[str] = mapped_column(String(16), default="standard", nullable=False)
    weigh_time: Mapped[time] = mapped_column(Time, default=time(8, 0), nullable=False)
    meal_windows: Mapped[dict[str, list[str]]] = mapped_column(
        JSON,
        default=lambda: {
            "breakfast": ["07:00", "10:00"],
            "lunch": ["11:00", "14:00"],
            "dinner": ["17:00", "21:00"],
        },
    )
    training_reminder_time: Mapped[time] = mapped_column(Time, default=time(18, 0), nullable=False)
    sleep_reminder_time: Mapped[time] = mapped_column(Time, default=time(23, 0), nullable=False)
    step_check_time: Mapped[time] = mapped_column(Time, default=time(20, 0), nullable=False)
    do_not_disturb_start: Mapped[time] = mapped_column(Time, default=time(23, 0), nullable=False)
    do_not_disturb_end: Mapped[time] = mapped_column(Time, default=time(7, 30), nullable=False)
    weekly_report_day: Mapped[int] = mapped_column(Integer, default=6, nullable=False)
    monthly_report_day: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    local_notifications_enabled: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )
    server_notifications_enabled: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False
    )


class HealthFollowup(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "health_followups"
    __table_args__ = (
        Index("ix_health_followup_user_date_status", "user_id", "recommended_date", "status"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    lab_test_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    recommended_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(24), default="suggested", nullable=False)
    source: Mapped[str] = mapped_column(String(40), default="user", nullable=False)
    source_entity_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class NotificationLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "notification_logs"
    __table_args__ = (
        UniqueConstraint("dedup_key", name="uq_notification_log_dedup"),
        Index("ix_notification_user_task_sent", "user_id", "task_id", "sent_at"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    task_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("daily_tasks.id", ondelete="SET NULL"), nullable=True
    )
    notification_type: Mapped[str] = mapped_column(String(48), nullable=False)
    channel: Mapped[str] = mapped_column(String(24), nullable=False)
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(String(24), default="prepared", nullable=False)
    reason: Mapped[str | None] = mapped_column(String(500), nullable=True)
    provider: Mapped[str] = mapped_column(String(64), nullable=False)
    dedup_key: Mapped[str] = mapped_column(String(240), nullable=False)
    interaction: Mapped[str | None] = mapped_column(String(32), nullable=True)
    completed_after_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)


class PushDevice(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "push_devices"
    __table_args__ = (
        UniqueConstraint("user_id", "device_id", name="uq_push_device_user_device"),
        Index("ix_push_device_user_active", "user_id", "active"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    device_id: Mapped[str] = mapped_column(String(160), nullable=False)
    platform: Mapped[str] = mapped_column(String(24), default="ios", nullable=False)
    environment: Mapped[str] = mapped_column(String(24), default="dev", nullable=False)
    token: Mapped[str] = mapped_column(String(512), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class HealthReport(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "health_reports"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "report_type", "period_start", "period_end", name="uq_health_report_period"
        ),
        Index("ix_health_report_user_type_period", "user_id", "report_type", "period_end"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    report_type: Mapped[str] = mapped_column(String(16), nullable=False)
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    metrics_snapshot: Mapped[dict[str, object]] = mapped_column(JSON, default=dict)
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    next_actions: Mapped[list[str]] = mapped_column(JSON, default=list)
    rule_version: Mapped[str] = mapped_column(String(32), nullable=False)
    prompt_version: Mapped[str] = mapped_column(String(32), nullable=False)
    input_snapshot_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    provider: Mapped[str] = mapped_column(String(64), nullable=False)
    model: Mapped[str] = mapped_column(String(160), nullable=False)
    regeneration_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class ProactiveCoachEvent(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "proactive_coach_events"
    __table_args__ = (
        UniqueConstraint("user_id", "event_date", "trigger_type", name="uq_proactive_trigger_day"),
        Index("ix_proactive_user_date", "user_id", "event_date"),
    )

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    event_date: Mapped[date] = mapped_column(Date, nullable=False)
    trigger_type: Mapped[str] = mapped_column(String(48), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    evidence_snapshot: Mapped[dict[str, object]] = mapped_column(JSON, default=dict)
    provider: Mapped[str] = mapped_column(String(64), nullable=False)
    model: Mapped[str] = mapped_column(String(160), nullable=False)
