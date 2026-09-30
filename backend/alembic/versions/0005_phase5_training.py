"""Phase 5 training, activity, recovery, and health synchronization."""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0005_phase5_training"
down_revision: str | None = "0004_phase4_diet_coach"
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
        "exercise_library",
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("normalized_name", sa.String(160), nullable=False),
        sa.Column("category", sa.String(64), nullable=False),
        sa.Column("movement_pattern", sa.String(32), nullable=False),
        sa.Column("primary_muscles", JSON_TYPE, nullable=False),
        sa.Column("secondary_muscles", JSON_TYPE, nullable=False),
        sa.Column("equipment", JSON_TYPE, nullable=False),
        sa.Column("difficulty", sa.String(24), nullable=False),
        sa.Column("instructions", sa.Text(), nullable=False),
        sa.Column("setup_instructions", JSON_TYPE, nullable=False),
        sa.Column("execution_cues", JSON_TYPE, nullable=False),
        sa.Column("common_mistakes", JSON_TYPE, nullable=False),
        sa.Column("safety_notes", JSON_TYPE, nullable=False),
        sa.Column("video_url", sa.String(500), nullable=True),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("unilateral", sa.Boolean(), nullable=False),
        sa.Column("bodyweight", sa.Boolean(), nullable=False),
        sa.Column("compound", sa.Boolean(), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        *_identity(),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("normalized_name"),
    )
    op.create_index("ix_exercise_library_normalized_name", "exercise_library", ["normalized_name"])
    op.create_index(
        "ix_exercise_library_movement_pattern",
        "exercise_library",
        ["movement_pattern"],
    )
    op.create_index("ix_exercise_library_active", "exercise_library", ["active"])

    op.create_table(
        "training_plans",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("goal", sa.String(64), nullable=False),
        sa.Column("difficulty", sa.String(24), nullable=False),
        sa.Column("weeks", sa.Integer(), nullable=False),
        sa.Column("sessions_per_week", sa.Integer(), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_training_plan_user_active", "training_plans", ["user_id", "active"])

    op.create_table(
        "training_days",
        sa.Column("plan_id", sa.Uuid(), nullable=False),
        sa.Column("day_number", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("focus", sa.String(120), nullable=False),
        sa.Column("estimated_duration_min", sa.Integer(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("order_index", sa.Integer(), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["plan_id"], ["training_plans.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("plan_id", "day_number", name="uq_training_day_number"),
        sa.UniqueConstraint("plan_id", "order_index", name="uq_training_day_order"),
    )
    op.create_table(
        "training_exercises",
        sa.Column("training_day_id", sa.Uuid(), nullable=False),
        sa.Column("exercise_id", sa.Uuid(), nullable=False),
        sa.Column("order_index", sa.Integer(), nullable=False),
        sa.Column("target_sets", sa.Integer(), nullable=False),
        sa.Column("target_rep_min", sa.Integer(), nullable=False),
        sa.Column("target_rep_max", sa.Integer(), nullable=False),
        sa.Column("target_weight_kg", sa.Numeric(8, 2), nullable=True),
        sa.Column("target_rpe", sa.Numeric(3, 1), nullable=True),
        sa.Column("target_rir", sa.Numeric(3, 1), nullable=True),
        sa.Column("rest_seconds", sa.Integer(), nullable=False),
        sa.Column("tempo", sa.String(32), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("progression_type", sa.String(32), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["training_day_id"], ["training_days.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["exercise_id"], ["exercise_library.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("training_day_id", "order_index", name="uq_training_exercise_order"),
    )
    op.create_table(
        "workout_sessions",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("training_day_id", sa.Uuid(), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_min", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("session_rpe", sa.Numeric(3, 1), nullable=True),
        sa.Column("energy_level", sa.Integer(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("idempotency_key", sa.String(128), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["training_day_id"], ["training_days.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "idempotency_key", name="uq_workout_user_idempotency"),
    )
    op.create_index("ix_workout_user_started", "workout_sessions", ["user_id", "started_at"])
    op.create_table(
        "workout_sets",
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("exercise_id", sa.Uuid(), nullable=False),
        sa.Column("set_number", sa.Integer(), nullable=False),
        sa.Column("set_type", sa.String(24), nullable=False),
        sa.Column("weight_kg", sa.Numeric(8, 2), nullable=False),
        sa.Column("reps", sa.Integer(), nullable=False),
        sa.Column("rpe", sa.Numeric(3, 1), nullable=True),
        sa.Column("rir", sa.Numeric(3, 1), nullable=True),
        sa.Column("completed", sa.Boolean(), nullable=False),
        sa.Column("rest_seconds", sa.Integer(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("idempotency_key", sa.String(128), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["session_id"], ["workout_sessions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["exercise_id"], ["exercise_library.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("session_id", "idempotency_key", name="uq_workout_set_idempotency"),
    )
    op.create_index(
        "ix_workout_set_session_exercise", "workout_sets", ["session_id", "exercise_id"]
    )
    op.create_table(
        "exercise_prs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("exercise_id", sa.Uuid(), nullable=False),
        sa.Column("workout_set_id", sa.Uuid(), nullable=True),
        sa.Column("pr_type", sa.String(24), nullable=False),
        sa.Column("value", sa.Numeric(12, 3), nullable=False),
        sa.Column("achieved_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("confidence", sa.String(16), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["exercise_id"], ["exercise_library.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["workout_set_id"], ["workout_sets.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "exercise_id", "pr_type", name="uq_exercise_pr_user_type"),
    )
    op.create_index("ix_exercise_pr_user_exercise", "exercise_prs", ["user_id", "exercise_id"])
    op.create_table(
        "pain_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("workout_session_id", sa.Uuid(), nullable=True),
        sa.Column("exercise_id", sa.Uuid(), nullable=True),
        sa.Column("body_area", sa.String(64), nullable=False),
        sa.Column("severity", sa.Integer(), nullable=False),
        sa.Column("symptoms", JSON_TYPE, nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("acute", sa.Boolean(), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["workout_session_id"], ["workout_sessions.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["exercise_id"], ["exercise_library.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_pain_user_created", "pain_logs", ["user_id", "created_at"])
    op.create_table(
        "training_adjustments",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("training_exercise_id", sa.Uuid(), nullable=True),
        sa.Column("adjustment_type", sa.String(32), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("previous_value", JSON_TYPE, nullable=False),
        sa.Column("proposed_value", JSON_TYPE, nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("evidence_snapshot", JSON_TYPE, nullable=False),
        sa.Column("rule_version", sa.String(32), nullable=False),
        sa.Column("idempotency_key", sa.String(128), nullable=True),
        sa.Column("applied_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["training_exercise_id"], ["training_exercises.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "idempotency_key", name="uq_training_adjustment_key"),
    )
    op.create_index(
        "ix_training_adjustment_user_status", "training_adjustments", ["user_id", "status"]
    )

    op.create_table(
        "activity_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("activity_date", sa.Date(), nullable=False),
        sa.Column("activity_type", sa.String(32), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_min", sa.Integer(), nullable=True),
        sa.Column("distance_km", sa.Numeric(10, 3), nullable=True),
        sa.Column("active_energy_kcal", sa.Numeric(10, 2), nullable=True),
        sa.Column("average_heart_rate", sa.Integer(), nullable=True),
        sa.Column("rpe", sa.Numeric(3, 1), nullable=True),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("source_record_id", sa.String(200), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "source", "source_record_id", name="uq_activity_source"),
    )
    op.create_index("ix_activity_user_date", "activity_logs", ["user_id", "activity_date"])
    op.create_table(
        "step_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("step_date", sa.Date(), nullable=False),
        sa.Column("steps", sa.Integer(), nullable=True),
        sa.Column("distance_km", sa.Numeric(10, 3), nullable=True),
        sa.Column("active_energy_kcal", sa.Numeric(10, 2), nullable=True),
        sa.Column("resting_heart_rate", sa.Integer(), nullable=True),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("source_record_id", sa.String(200), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "step_date", "source", name="uq_step_daily_source"),
        sa.UniqueConstraint("user_id", "source", "source_record_id", name="uq_step_source_record"),
    )
    op.create_index("ix_step_user_date", "step_logs", ["user_id", "step_date"])
    op.create_table(
        "sleep_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("sleep_start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("sleep_end", sa.DateTime(timezone=True), nullable=False),
        sa.Column("duration_min", sa.Integer(), nullable=False),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("sleep_stages", JSON_TYPE, nullable=False),
        sa.Column("quality", sa.Integer(), nullable=True),
        sa.Column("source_record_id", sa.String(200), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "source", "source_record_id", name="uq_sleep_source_record"),
    )
    op.create_index("ix_sleep_user_start", "sleep_logs", ["user_id", "sleep_start"])
    op.create_table(
        "health_sync_state",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(32), nullable=False),
        sa.Column("data_type", sa.String(40), nullable=False),
        sa.Column("last_sync_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cursor", sa.Text(), nullable=True),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("error_summary", sa.String(500), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "provider", "data_type", name="uq_health_sync_type"),
    )
    op.create_table(
        "health_permission_state",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(32), nullable=False),
        sa.Column("data_type", sa.String(40), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("authorization_status", sa.String(24), nullable=False),
        sa.Column("requested_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "provider", "data_type", name="uq_health_permission_type"),
    )
    op.create_table(
        "recovery_snapshots",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("snapshot_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("sleep_duration_min", sa.Integer(), nullable=True),
        sa.Column("subjective_fatigue", sa.Integer(), nullable=True),
        sa.Column("last_session_rpe", sa.Numeric(3, 1), nullable=True),
        sa.Column("resting_heart_rate", sa.Integer(), nullable=True),
        sa.Column("resting_heart_rate_baseline", sa.Numeric(6, 2), nullable=True),
        sa.Column("pain_severity", sa.Integer(), nullable=True),
        sa.Column("recent_training_count", sa.Integer(), nullable=False),
        sa.Column("reasons", JSON_TYPE, nullable=False),
        sa.Column("evidence_snapshot", JSON_TYPE, nullable=False),
        sa.Column("rule_version", sa.String(32), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "snapshot_date", name="uq_recovery_user_date"),
    )
    op.create_index("ix_recovery_user_date", "recovery_snapshots", ["user_id", "snapshot_date"])


def downgrade() -> None:
    for table, indexes in [
        ("recovery_snapshots", ["ix_recovery_user_date"]),
        ("health_permission_state", []),
        ("health_sync_state", []),
        ("sleep_logs", ["ix_sleep_user_start"]),
        ("step_logs", ["ix_step_user_date"]),
        ("activity_logs", ["ix_activity_user_date"]),
        ("training_adjustments", ["ix_training_adjustment_user_status"]),
        ("pain_logs", ["ix_pain_user_created"]),
        ("exercise_prs", ["ix_exercise_pr_user_exercise"]),
        ("workout_sets", ["ix_workout_set_session_exercise"]),
        ("workout_sessions", ["ix_workout_user_started"]),
        ("training_exercises", []),
        ("training_days", []),
        ("training_plans", ["ix_training_plan_user_active"]),
        (
            "exercise_library",
            [
                "ix_exercise_library_active",
                "ix_exercise_library_movement_pattern",
                "ix_exercise_library_normalized_name",
            ],
        ),
    ]:
        for index in indexes:
            op.drop_index(index, table_name=table)
        op.drop_table(table)
