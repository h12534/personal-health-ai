import os

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_phase4_migration_uses_jsonb_and_required_tables() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    async with engine.connect() as connection:
        tables = set(
            (
                await connection.scalars(
                    text(
                        "SELECT table_name FROM information_schema.tables "
                        "WHERE table_schema = 'public'"
                    )
                )
            ).all()
        )
        assert {
            "diet_adjustments",
            "hunger_logs",
            "canteens",
            "canteen_stalls",
            "canteen_dishes",
            "personal_dietary_memories",
            "personal_energy_models",
            "saved_meals",
            "saved_meal_items",
            "coach_conversations",
            "coach_messages",
        } <= tables
        json_types = set(
            (
                await connection.scalars(
                    text(
                        "SELECT data_type FROM information_schema.columns "
                        "WHERE (table_name, column_name) IN "
                        "(('diet_adjustments', 'evidence_snapshot'), "
                        "('canteen_dishes', 'tags'), "
                        "('personal_energy_models', 'evidence_snapshot'), "
                        "('coach_messages', 'structured_payload'))"
                    )
                )
            ).all()
        )
        assert json_types == {"jsonb"}
        columns = set(
            (
                await connection.scalars(
                    text(
                        "SELECT column_name FROM information_schema.columns "
                        "WHERE table_name = 'health_profiles'"
                    )
                )
            ).all()
        )
        assert {
            "current_goal_phase",
            "allow_auto_diet_adjustment",
            "adjustment_cooldown_days",
        } <= columns
    await engine.dispose()
