"""Phase 2 food, meal, and nutrition goal tables."""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0002_phase2_nutrition"
down_revision: str | None = "0001_phase1_core"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "food_items",
        sa.Column("owner_user_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("normalized_name", sa.String(length=200), nullable=False),
        sa.Column("brand", sa.String(length=200), nullable=True),
        sa.Column("category", sa.String(length=64), nullable=False),
        sa.Column("source", sa.String(length=64), nullable=False),
        sa.Column("source_id", sa.String(length=200), nullable=True),
        sa.Column("data_source_name", sa.String(length=300), nullable=True),
        sa.Column("data_source_url", sa.Text(), nullable=True),
        sa.Column("is_custom", sa.Boolean(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("serving_description", sa.String(length=200), nullable=True),
        sa.Column("serving_unit", sa.String(length=32), nullable=True),
        sa.Column("serving_weight_g", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("calories_per_100g", sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column("protein_per_100g", sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column("carbs_per_100g", sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column("fat_per_100g", sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column("fiber_per_100g", sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column("sugar_per_100g", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("sodium_mg_per_100g", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("potassium_mg_per_100g", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("calcium_mg_per_100g", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("iron_mg_per_100g", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "(is_custom = false) OR (owner_user_id IS NOT NULL)",
            name="ck_custom_food_has_owner",
        ),
        sa.ForeignKeyConstraint(["owner_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("source", "source_id", name="uq_food_source_id"),
    )
    op.create_index(op.f("ix_food_items_category"), "food_items", ["category"])
    op.create_index(op.f("ix_food_items_owner_user_id"), "food_items", ["owner_user_id"])
    op.create_index("ix_food_normalized_name", "food_items", ["normalized_name"])
    op.create_index("ix_food_owner_active", "food_items", ["owner_user_id", "is_active"])
    op.create_table(
        "food_aliases",
        sa.Column("food_id", sa.Uuid(), nullable=False),
        sa.Column("alias", sa.String(length=200), nullable=False),
        sa.Column("normalized_alias", sa.String(length=200), nullable=False),
        sa.Column("language", sa.String(length=16), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["food_id"], ["food_items.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("food_id", "normalized_alias", name="uq_food_alias_normalized"),
    )
    op.create_index("ix_food_alias_normalized", "food_aliases", ["normalized_alias"])
    op.create_table(
        "food_favorites",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("food_id", sa.Uuid(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["food_id"], ["food_items.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "food_id", name="uq_favorite_user_food"),
    )
    op.create_index("ix_favorite_user_created", "food_favorites", ["user_id", "created_at"])
    op.create_table(
        "meal_logs",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("meal_type", sa.String(length=32), nullable=False),
        sa.Column("eaten_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("idempotency_key", sa.String(length=128), nullable=True),
        sa.Column("total_calories", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("total_protein", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("total_carbs", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("total_fat", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("total_fiber", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "idempotency_key", name="uq_meal_user_idempotency"),
    )
    op.create_index(op.f("ix_meal_logs_meal_type"), "meal_logs", ["meal_type"])
    op.create_index("ix_meal_user_eaten_at", "meal_logs", ["user_id", "eaten_at"])
    op.create_table(
        "meal_items",
        sa.Column("meal_id", sa.Uuid(), nullable=False),
        sa.Column("food_id", sa.Uuid(), nullable=True),
        sa.Column("food_name_snapshot", sa.String(length=200), nullable=False),
        sa.Column("amount", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("amount_unit", sa.String(length=32), nullable=False),
        sa.Column("weight_g", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("calories", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("protein", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("carbs", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("fat", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("fiber", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("nutrition_source", sa.String(length=64), nullable=False),
        sa.Column("idempotency_key", sa.String(length=128), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["food_id"], ["food_items.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["meal_id"], ["meal_logs.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("meal_id", "idempotency_key", name="uq_meal_item_idempotency"),
    )
    op.create_index("ix_meal_item_meal_active", "meal_items", ["meal_id", "deleted_at"])
    op.create_table(
        "nutrition_goals",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("effective_from", sa.Date(), nullable=False),
        sa.Column("effective_to", sa.Date(), nullable=True),
        sa.Column("calorie_target", sa.Integer(), nullable=False),
        sa.Column("protein_target_g", sa.Numeric(precision=10, scale=2), nullable=False),
        sa.Column("carbs_target_g", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("fat_target_g", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("fiber_target_g", sa.Numeric(precision=10, scale=2), nullable=False),
        sa.Column("water_target_ml", sa.Integer(), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_goal_user_effective", "nutrition_goals", ["user_id", "effective_from"])


def downgrade() -> None:
    op.drop_index("ix_goal_user_effective", table_name="nutrition_goals")
    op.drop_table("nutrition_goals")
    op.drop_index("ix_meal_item_meal_active", table_name="meal_items")
    op.drop_table("meal_items")
    op.drop_index("ix_meal_user_eaten_at", table_name="meal_logs")
    op.drop_index(op.f("ix_meal_logs_meal_type"), table_name="meal_logs")
    op.drop_table("meal_logs")
    op.drop_index("ix_favorite_user_created", table_name="food_favorites")
    op.drop_table("food_favorites")
    op.drop_index("ix_food_alias_normalized", table_name="food_aliases")
    op.drop_table("food_aliases")
    op.drop_index("ix_food_owner_active", table_name="food_items")
    op.drop_index("ix_food_normalized_name", table_name="food_items")
    op.drop_index(op.f("ix_food_items_owner_user_id"), table_name="food_items")
    op.drop_index(op.f("ix_food_items_category"), table_name="food_items")
    op.drop_table("food_items")
