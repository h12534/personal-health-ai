"""Phase 1 identity, profile, and weight tables."""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0001_phase1_core"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("password_hash", sa.String(length=512), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("is_superuser", sa.Boolean(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_users_email"), "users", ["email"], unique=True)
    op.create_table(
        "auth_sessions",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("refresh_token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("user_agent", sa.String(length=512), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_auth_sessions_expires_at"), "auth_sessions", ["expires_at"])
    op.create_index(
        op.f("ix_auth_sessions_refresh_token_hash"),
        "auth_sessions",
        ["refresh_token_hash"],
        unique=True,
    )
    op.create_index(op.f("ix_auth_sessions_user_id"), "auth_sessions", ["user_id"])
    op.create_table(
        "health_profiles",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("birth_date", sa.Date(), nullable=True),
        sa.Column("sex", sa.String(length=32), nullable=True),
        sa.Column("height_cm", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("target_weight_kg", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("waist_cm", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("body_fat_percent", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("resting_heart_rate", sa.Integer(), nullable=True),
        sa.Column("activity_level", sa.String(length=32), nullable=True),
        sa.Column("primary_goal", sa.String(length=64), nullable=False),
        sa.Column("training_experience", sa.String(length=32), nullable=True),
        sa.Column("daily_exercise_minutes", sa.Integer(), nullable=True),
        sa.Column("school_life", sa.Boolean(), nullable=False),
        sa.Column("available_equipment", sa.JSON(), nullable=False),
        sa.Column("dietary_environment", sa.JSON(), nullable=False),
        sa.Column("food_preferences", sa.JSON(), nullable=False),
        sa.Column("disliked_foods", sa.JSON(), nullable=False),
        sa.Column("allergies", sa.JSON(), nullable=False),
        sa.Column("known_health_risks", sa.JSON(), nullable=False),
        sa.Column("medications", sa.JSON(), nullable=False),
        sa.Column("doctor_advice", sa.Text(), nullable=True),
        sa.Column("timezone", sa.String(length=64), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_health_profiles_user_id"), "health_profiles", ["user_id"], unique=True)
    op.create_table(
        "weight_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("measured_on", sa.Date(), nullable=False),
        sa.Column("weight_kg", sa.Numeric(precision=5, scale=2), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "measured_on", name="uq_weight_user_date"),
    )
    op.create_index("ix_weight_user_measured_desc", "weight_logs", ["user_id", "measured_on"])


def downgrade() -> None:
    op.drop_index("ix_weight_user_measured_desc", table_name="weight_logs")
    op.drop_table("weight_logs")
    op.drop_index(op.f("ix_health_profiles_user_id"), table_name="health_profiles")
    op.drop_table("health_profiles")
    op.drop_index(op.f("ix_auth_sessions_user_id"), table_name="auth_sessions")
    op.drop_index(op.f("ix_auth_sessions_refresh_token_hash"), table_name="auth_sessions")
    op.drop_index(op.f("ix_auth_sessions_expires_at"), table_name="auth_sessions")
    op.drop_table("auth_sessions")
    op.drop_index(op.f("ix_users_email"), table_name="users")
    op.drop_table("users")
