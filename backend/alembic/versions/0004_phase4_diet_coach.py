"""Phase 4 private AI diet coach and personalized planning."""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0004_phase4_diet_coach"
down_revision: str | None = "0003_phase3_meal_vision"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSON_TYPE = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    ]


def upgrade() -> None:
    op.add_column(
        "health_profiles",
        sa.Column("current_goal_phase", sa.String(32), server_default="fat_loss", nullable=False),
    )
    op.add_column(
        "health_profiles",
        sa.Column(
            "allow_auto_diet_adjustment", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
    )
    op.add_column(
        "health_profiles",
        sa.Column("adjustment_cooldown_days", sa.Integer(), server_default="14", nullable=False),
    )
    op.create_table(
        "diet_adjustments",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("previous_goal_id", sa.Uuid(), nullable=True),
        sa.Column("resulting_goal_id", sa.Uuid(), nullable=True),
        sa.Column("previous_calorie_target", sa.Integer(), nullable=False),
        sa.Column("proposed_calorie_target", sa.Integer(), nullable=False),
        sa.Column("previous_protein_target_g", sa.Numeric(10, 2), nullable=False),
        sa.Column("proposed_protein_target_g", sa.Numeric(10, 2), nullable=False),
        sa.Column("reason_code", sa.String(64), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("evidence_snapshot", JSON_TYPE, nullable=False),
        sa.Column("rule_version", sa.String(32), nullable=False),
        sa.Column("input_snapshot_hash", sa.String(64), nullable=False),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("approved_by", sa.String(32), nullable=True),
        sa.Column("evaluate_after", sa.Date(), nullable=True),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("idempotency_key", sa.String(128), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["previous_goal_id"], ["nutrition_goals.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["resulting_goal_id"], ["nutrition_goals.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "idempotency_key", name="uq_adjustment_user_idempotency"),
    )
    op.create_index(
        "ix_diet_adjustment_user_created", "diet_adjustments", ["user_id", "created_at"]
    )
    op.create_index("ix_diet_adjustments_status", "diet_adjustments", ["status"])
    op.create_table(
        "hunger_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("logged_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("hunger_level", sa.Integer(), nullable=False),
        sa.Column("craving_level", sa.Integer(), nullable=True),
        sa.Column("context", sa.String(64), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_hunger_user_logged", "hunger_logs", ["user_id", "logged_at"])
    op.create_table(
        "canteens",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("campus", sa.String(200), nullable=True),
        sa.Column("location", sa.String(300), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_canteen_user_active", "canteens", ["user_id", "is_active"])
    op.create_table(
        "canteen_stalls",
        sa.Column("canteen_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("cuisine", sa.String(100), nullable=True),
        sa.Column("floor", sa.String(64), nullable=True),
        sa.Column("location_note", sa.String(300), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["canteen_id"], ["canteens.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_stall_canteen_active", "canteen_stalls", ["canteen_id", "is_active"])
    op.create_table(
        "canteen_dishes",
        sa.Column("stall_id", sa.Uuid(), nullable=False),
        sa.Column("food_item_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("calories", sa.Numeric(10, 2), nullable=False),
        sa.Column("protein_g", sa.Numeric(10, 2), nullable=False),
        sa.Column("carbs_g", sa.Numeric(10, 2), nullable=False),
        sa.Column("fat_g", sa.Numeric(10, 2), nullable=False),
        sa.Column("fiber_g", sa.Numeric(10, 2), nullable=False),
        sa.Column("portion_description", sa.String(200), nullable=True),
        sa.Column("average_weight_g", sa.Numeric(10, 2), nullable=True),
        sa.Column("confidence", sa.Numeric(4, 3), nullable=False),
        sa.Column("times_logged", sa.Integer(), nullable=False),
        sa.Column("last_seen", sa.DateTime(timezone=True), nullable=True),
        sa.Column("favorite", sa.Boolean(), nullable=False),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("tags", JSON_TYPE, nullable=False),
        sa.Column("is_available", sa.Boolean(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["stall_id"], ["canteen_stalls.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["food_item_id"], ["food_items.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_dish_stall_active", "canteen_dishes", ["stall_id", "is_available"])
    op.create_table(
        "personal_dietary_memories",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(40), nullable=False),
        sa.Column("memory_key", sa.String(120), nullable=True),
        sa.Column("value", sa.String(500), nullable=False),
        sa.Column("normalized_value", sa.String(500), nullable=False),
        sa.Column("confidence", sa.Numeric(4, 3), nullable=False),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("last_confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "kind", "normalized_value", name="uq_diet_memory_value"),
    )
    op.create_index("ix_diet_memory_user_kind", "personal_dietary_memories", ["user_id", "kind"])
    op.create_table(
        "personal_energy_models",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("calculated_on", sa.Date(), nullable=False),
        sa.Column("formula_tdee", sa.Integer(), nullable=False),
        sa.Column("observed_tdee", sa.Integer(), nullable=True),
        sa.Column("blended_tdee", sa.Integer(), nullable=False),
        sa.Column("confidence", sa.Numeric(4, 3), nullable=False),
        sa.Column("sample_days", sa.Integer(), nullable=False),
        sa.Column("completeness", sa.Numeric(4, 3), nullable=False),
        sa.Column("method_version", sa.String(32), nullable=False),
        sa.Column("evidence_snapshot", JSON_TYPE, nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "calculated_on", name="uq_energy_model_user_date"),
    )
    op.create_index(
        "ix_energy_model_user_date", "personal_energy_models", ["user_id", "calculated_on"]
    )
    op.create_table(
        "saved_meals",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("meal_type", sa.String(32), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_saved_meal_user_active", "saved_meals", ["user_id", "deleted_at"])
    op.create_table(
        "saved_meal_items",
        sa.Column("saved_meal_id", sa.Uuid(), nullable=False),
        sa.Column("food_id", sa.Uuid(), nullable=True),
        sa.Column("food_name_snapshot", sa.String(200), nullable=False),
        sa.Column("amount", sa.Numeric(12, 3), nullable=False),
        sa.Column("amount_unit", sa.String(32), nullable=False),
        sa.Column("weight_g", sa.Numeric(12, 3), nullable=False),
        sa.Column("calories", sa.Numeric(12, 3), nullable=False),
        sa.Column("protein", sa.Numeric(12, 3), nullable=False),
        sa.Column("carbs", sa.Numeric(12, 3), nullable=False),
        sa.Column("fat", sa.Numeric(12, 3), nullable=False),
        sa.Column("fiber", sa.Numeric(12, 3), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["saved_meal_id"], ["saved_meals.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["food_id"], ["food_items.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "coach_conversations",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(200), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_coach_conversation_user_updated", "coach_conversations", ["user_id", "updated_at"]
    )
    op.create_table(
        "coach_messages",
        sa.Column("conversation_id", sa.Uuid(), nullable=False),
        sa.Column("role", sa.String(16), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("intent", sa.String(48), nullable=True),
        sa.Column("provider", sa.String(64), nullable=True),
        sa.Column("model", sa.String(128), nullable=True),
        sa.Column("prompt_version", sa.String(32), nullable=True),
        sa.Column("structured_payload", JSON_TYPE, nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(
            ["conversation_id"], ["coach_conversations.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_coach_message_conversation_created", "coach_messages", ["conversation_id", "created_at"]
    )


def downgrade() -> None:
    for index_name, table_name in [
        ("ix_coach_message_conversation_created", "coach_messages"),
        ("ix_coach_conversation_user_updated", "coach_conversations"),
    ]:
        op.drop_index(index_name, table_name=table_name)
        op.drop_table(table_name)
    op.drop_table("saved_meal_items")
    op.drop_index("ix_saved_meal_user_active", table_name="saved_meals")
    op.drop_table("saved_meals")
    op.drop_index("ix_energy_model_user_date", table_name="personal_energy_models")
    op.drop_table("personal_energy_models")
    op.drop_index("ix_diet_memory_user_kind", table_name="personal_dietary_memories")
    op.drop_table("personal_dietary_memories")
    op.drop_index("ix_dish_stall_active", table_name="canteen_dishes")
    op.drop_table("canteen_dishes")
    op.drop_index("ix_stall_canteen_active", table_name="canteen_stalls")
    op.drop_table("canteen_stalls")
    op.drop_index("ix_canteen_user_active", table_name="canteens")
    op.drop_table("canteens")
    op.drop_index("ix_hunger_user_logged", table_name="hunger_logs")
    op.drop_table("hunger_logs")
    op.drop_index("ix_diet_adjustments_status", table_name="diet_adjustments")
    op.drop_index("ix_diet_adjustment_user_created", table_name="diet_adjustments")
    op.drop_table("diet_adjustments")
    op.drop_column("health_profiles", "adjustment_cooldown_days")
    op.drop_column("health_profiles", "allow_auto_diet_adjustment")
    op.drop_column("health_profiles", "current_goal_phase")
