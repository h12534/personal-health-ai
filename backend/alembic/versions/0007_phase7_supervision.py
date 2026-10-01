"""Phase 7 active supervision, reports, notifications, and follow-ups."""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0007_phase7_supervision"
down_revision: str | None = "0006_phase6_health_knowledge"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSON_TYPE = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")


def _identity() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    ]


def upgrade() -> None:
    op.create_table(
        "daily_tasks",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("task_date", sa.Date(), nullable=False),
        sa.Column("task_type", sa.String(40), nullable=False),
        sa.Column("title", sa.String(160), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("priority", sa.Integer(), nullable=False),
        sa.Column("scheduled_time", sa.Time(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("source", sa.String(40), nullable=False),
        sa.Column("source_entity_id", sa.String(128), nullable=True),
        sa.Column("reminder_policy", JSON_TYPE, nullable=False),
        sa.Column("dedup_key", sa.String(240), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "task_date", "dedup_key", name="uq_daily_task_dedup"),
    )
    op.create_index(
        "ix_daily_task_user_date_status", "daily_tasks", ["user_id", "task_date", "status"]
    )

    op.create_table(
        "reminder_preferences",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("mode", sa.String(16), nullable=False),
        sa.Column("weigh_time", sa.Time(), nullable=False),
        sa.Column("meal_windows", JSON_TYPE, nullable=False),
        sa.Column("training_reminder_time", sa.Time(), nullable=False),
        sa.Column("sleep_reminder_time", sa.Time(), nullable=False),
        sa.Column("step_check_time", sa.Time(), nullable=False),
        sa.Column("do_not_disturb_start", sa.Time(), nullable=False),
        sa.Column("do_not_disturb_end", sa.Time(), nullable=False),
        sa.Column("weekly_report_day", sa.Integer(), nullable=False),
        sa.Column("monthly_report_day", sa.Integer(), nullable=False),
        sa.Column("local_notifications_enabled", sa.Boolean(), nullable=False),
        sa.Column("server_notifications_enabled", sa.Boolean(), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", name="uq_reminder_preference_user"),
    )

    op.create_table(
        "health_followups",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("lab_test_code", sa.String(80), nullable=True),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("recommended_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("source", sa.String(40), nullable=False),
        sa.Column("source_entity_id", sa.String(128), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_health_followup_user_date_status",
        "health_followups",
        ["user_id", "recommended_date", "status"],
    )

    op.create_table(
        "push_devices",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.String(160), nullable=False),
        sa.Column("platform", sa.String(24), nullable=False),
        sa.Column("token", sa.String(512), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "device_id", name="uq_push_device_user_device"),
    )
    op.create_index("ix_push_device_user_active", "push_devices", ["user_id", "active"])

    op.create_table(
        "health_reports",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("report_type", sa.String(16), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column("metrics_snapshot", JSON_TYPE, nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("next_actions", JSON_TYPE, nullable=False),
        sa.Column("rule_version", sa.String(32), nullable=False),
        sa.Column("prompt_version", sa.String(32), nullable=False),
        sa.Column("input_snapshot_hash", sa.String(64), nullable=False),
        sa.Column("provider", sa.String(64), nullable=False),
        sa.Column("model", sa.String(160), nullable=False),
        sa.Column("regeneration_count", sa.Integer(), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id", "report_type", "period_start", "period_end", name="uq_health_report_period"
        ),
    )
    op.create_index(
        "ix_health_report_user_type_period",
        "health_reports",
        ["user_id", "report_type", "period_end"],
    )

    op.create_table(
        "proactive_coach_events",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("event_date", sa.Date(), nullable=False),
        sa.Column("trigger_type", sa.String(48), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("evidence_snapshot", JSON_TYPE, nullable=False),
        sa.Column("provider", sa.String(64), nullable=False),
        sa.Column("model", sa.String(160), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id", "event_date", "trigger_type", name="uq_proactive_trigger_day"
        ),
    )
    op.create_index("ix_proactive_user_date", "proactive_coach_events", ["user_id", "event_date"])

    op.create_table(
        "notification_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("task_id", sa.Uuid(), nullable=True),
        sa.Column("notification_type", sa.String(48), nullable=False),
        sa.Column("channel", sa.String(24), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("reason", sa.String(500), nullable=True),
        sa.Column("provider", sa.String(64), nullable=False),
        sa.Column("dedup_key", sa.String(240), nullable=False),
        sa.Column("interaction", sa.String(32), nullable=True),
        sa.Column("completed_after_minutes", sa.Integer(), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["task_id"], ["daily_tasks.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("dedup_key", name="uq_notification_log_dedup"),
    )
    op.create_index(
        "ix_notification_user_task_sent",
        "notification_logs",
        ["user_id", "task_id", "sent_at"],
    )


def downgrade() -> None:
    for table, indexes in [
        ("notification_logs", ["ix_notification_user_task_sent"]),
        ("proactive_coach_events", ["ix_proactive_user_date"]),
        ("health_reports", ["ix_health_report_user_type_period"]),
        ("push_devices", ["ix_push_device_user_active"]),
        ("health_followups", ["ix_health_followup_user_date_status"]),
        ("reminder_preferences", []),
        ("daily_tasks", ["ix_daily_task_user_date_status"]),
    ]:
        for index in indexes:
            op.drop_index(index, table_name=table)
        op.drop_table(table)
