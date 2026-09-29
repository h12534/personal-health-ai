"""Phase 3 meal photo analysis, drafts, personal memory, and AI usage."""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0003_phase3_meal_vision"
down_revision: str | None = "0002_phase2_nutrition"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSON_TYPE = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")


def upgrade() -> None:
    op.add_column(
        "health_profiles",
        sa.Column(
            "allow_third_party_vision", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
    )
    op.add_column(
        "health_profiles",
        sa.Column("retain_meal_images", sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    op.create_table(
        "meal_images",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("object_key", sa.String(500), nullable=False),
        sa.Column("content_type", sa.String(64), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("width", sa.Integer(), nullable=False),
        sa.Column("height", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(64), nullable=False),
        sa.Column("retention_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("object_key"),
    )
    op.create_index("ix_meal_image_user_created", "meal_images", ["user_id", "created_at"])
    op.create_table(
        "meal_analysis_sessions",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("image_id", sa.Uuid(), nullable=False),
        sa.Column("confirmed_meal_id", sa.Uuid(), nullable=True),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("provider", sa.String(64), nullable=False),
        sa.Column("model", sa.String(128), nullable=False),
        sa.Column("prompt_version", sa.String(64), nullable=False),
        sa.Column("idempotency_key", sa.String(128), nullable=True),
        sa.Column("confirm_idempotency_key", sa.String(128), nullable=True),
        sa.Column("location_context", sa.String(100), nullable=True),
        sa.Column("meal_type", sa.String(32), nullable=True),
        sa.Column("eaten_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("overall_confidence", sa.Numeric(5, 4), nullable=True),
        sa.Column("warnings", JSON_TYPE, nullable=False),
        sa.Column("raw_provider_response", JSON_TYPE, nullable=True),
        sa.Column("attempt_count", sa.Integer(), nullable=False),
        sa.Column("reanalysis_count", sa.Integer(), nullable=False),
        sa.Column("error_code", sa.String(100), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["confirmed_meal_id"], ["meal_logs.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["image_id"], ["meal_images.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "idempotency_key", name="uq_analysis_user_idempotency"),
    )
    op.create_index("ix_analysis_user_created", "meal_analysis_sessions", ["user_id", "created_at"])
    op.create_index(
        "ix_analysis_status_expires", "meal_analysis_sessions", ["status", "expires_at"]
    )
    op.create_index("ix_analysis_image", "meal_analysis_sessions", ["image_id"])
    op.create_table(
        "meal_analysis_items",
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("matched_food_id", sa.Uuid(), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("detected_name", sa.String(200), nullable=False),
        sa.Column("match_type", sa.String(32), nullable=False),
        sa.Column("match_confidence", sa.Numeric(5, 4), nullable=False),
        sa.Column("recognition_confidence", sa.Numeric(5, 4), nullable=False),
        sa.Column("portion_confidence", sa.Numeric(5, 4), nullable=False),
        sa.Column("estimated_weight_g", sa.Numeric(10, 3), nullable=False),
        sa.Column("min_weight_g", sa.Numeric(10, 3), nullable=False),
        sa.Column("max_weight_g", sa.Numeric(10, 3), nullable=False),
        sa.Column("original_ai_weight_g", sa.Numeric(10, 3), nullable=True),
        sa.Column("portion_description", sa.String(300), nullable=True),
        sa.Column("cooking_method", sa.String(100), nullable=True),
        sa.Column("visible_components", JSON_TYPE, nullable=False),
        sa.Column("possible_hidden_ingredients", JSON_TYPE, nullable=False),
        sa.Column("is_hidden_ingredient", sa.Boolean(), nullable=False),
        sa.Column("user_modified", sa.Boolean(), nullable=False),
        sa.Column("calories", sa.Numeric(12, 3), nullable=False),
        sa.Column("protein", sa.Numeric(12, 3), nullable=False),
        sa.Column("carbs", sa.Numeric(12, 3), nullable=False),
        sa.Column("fat", sa.Numeric(12, 3), nullable=False),
        sa.Column("fiber", sa.Numeric(12, 3), nullable=False),
        sa.Column("min_calories", sa.Numeric(12, 3), nullable=False),
        sa.Column("max_calories", sa.Numeric(12, 3), nullable=False),
        sa.Column("min_protein", sa.Numeric(12, 3), nullable=False),
        sa.Column("max_protein", sa.Numeric(12, 3), nullable=False),
        sa.Column("min_carbs", sa.Numeric(12, 3), nullable=False),
        sa.Column("max_carbs", sa.Numeric(12, 3), nullable=False),
        sa.Column("min_fat", sa.Numeric(12, 3), nullable=False),
        sa.Column("max_fat", sa.Numeric(12, 3), nullable=False),
        sa.Column("min_fiber", sa.Numeric(12, 3), nullable=False),
        sa.Column("max_fiber", sa.Numeric(12, 3), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["matched_food_id"], ["food_items.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["session_id"], ["meal_analysis_sessions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_analysis_item_session_active", "meal_analysis_items", ["session_id", "deleted_at"]
    )
    op.create_table(
        "personal_food_memories",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("normalized_detected_label", sa.String(200), nullable=False),
        sa.Column("confirmed_food_id", sa.Uuid(), nullable=False),
        sa.Column("location_context", sa.String(100), nullable=False),
        sa.Column("average_ai_weight_g", sa.Numeric(10, 3), nullable=False),
        sa.Column("average_confirmed_weight_g", sa.Numeric(10, 3), nullable=False),
        sa.Column("sample_count", sa.Integer(), nullable=False),
        sa.Column("confidence", sa.Numeric(5, 4), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["confirmed_food_id"], ["food_items.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_food_memory_user_label",
        "personal_food_memories",
        ["user_id", "normalized_detected_label"],
    )
    op.create_index(
        "uq_food_memory_context",
        "personal_food_memories",
        ["user_id", "normalized_detected_label", "confirmed_food_id", "location_context"],
        unique=True,
    )
    op.create_table(
        "ai_usage_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("analysis_session_id", sa.Uuid(), nullable=True),
        sa.Column("provider", sa.String(64), nullable=False),
        sa.Column("model", sa.String(128), nullable=False),
        sa.Column("task", sa.String(64), nullable=False),
        sa.Column("input_tokens", sa.Integer(), nullable=True),
        sa.Column("output_tokens", sa.Integer(), nullable=True),
        sa.Column("image_count", sa.Integer(), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=False),
        sa.Column("estimated_cost", sa.Numeric(12, 6), nullable=True),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("error_code", sa.String(100), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["analysis_session_id"], ["meal_analysis_sessions.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ai_usage_user_created", "ai_usage_logs", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_ai_usage_user_created", table_name="ai_usage_logs")
    op.drop_table("ai_usage_logs")
    op.drop_index("uq_food_memory_context", table_name="personal_food_memories")
    op.drop_index("ix_food_memory_user_label", table_name="personal_food_memories")
    op.drop_table("personal_food_memories")
    op.drop_index("ix_analysis_item_session_active", table_name="meal_analysis_items")
    op.drop_table("meal_analysis_items")
    op.drop_index("ix_analysis_image", table_name="meal_analysis_sessions")
    op.drop_index("ix_analysis_status_expires", table_name="meal_analysis_sessions")
    op.drop_index("ix_analysis_user_created", table_name="meal_analysis_sessions")
    op.drop_table("meal_analysis_sessions")
    op.drop_index("ix_meal_image_user_created", table_name="meal_images")
    op.drop_table("meal_images")
    op.drop_column("health_profiles", "retain_meal_images")
    op.drop_column("health_profiles", "allow_third_party_vision")
