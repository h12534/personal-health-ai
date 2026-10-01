import json
import os
from datetime import UTC, date, datetime
from uuid import uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_phase7_postgres_jsonb_dedup_and_cascade() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    user_id = uuid4()
    now = datetime.now(UTC)
    async with engine.begin() as connection:
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
            "daily_tasks",
            "reminder_preferences",
            "health_followups",
            "notification_logs",
            "push_devices",
            "health_reports",
            "proactive_coach_events",
        } <= tables
        json_types = set(
            (
                await connection.scalars(
                    text(
                        "SELECT data_type FROM information_schema.columns "
                        "WHERE (table_name, column_name) IN "
                        "(('daily_tasks', 'reminder_policy'), "
                        "('health_reports', 'metrics_snapshot'), "
                        "('proactive_coach_events', 'evidence_snapshot'))"
                    )
                )
            ).all()
        )
        assert json_types == {"jsonb"}
        constraint = await connection.scalar(
            text(
                "SELECT constraint_name FROM information_schema.table_constraints "
                "WHERE table_name = 'daily_tasks' "
                "AND constraint_name = 'uq_daily_task_dedup'"
            )
        )
        assert constraint == "uq_daily_task_dedup"
        await connection.execute(
            text(
                "INSERT INTO users "
                "(id, email, password_hash, is_active, is_superuser, created_at, updated_at) "
                "VALUES (:id, :email, 'test', true, false, :now, :now)"
            ),
            {"id": user_id, "email": f"phase7-{user_id}@example.com", "now": now},
        )
        parameters = {
            "id": uuid4(),
            "user_id": user_id,
            "task_date": date(2026, 10, 1),
            "policy": json.dumps({"cooldown_hours": 4}),
            "now": now,
        }
        statement = text(
            """
            INSERT INTO daily_tasks
              (id, user_id, task_date, task_type, title, description, status,
               priority, scheduled_time, completed_at, source, source_entity_id,
               reminder_policy, dedup_key, created_at, updated_at)
            VALUES
              (:id, :user_id, :task_date, 'weigh_in', 'Morning weight', 'Record weight',
               'pending', 100, '08:00', NULL, 'daily_engine', NULL,
               CAST(:policy AS jsonb), 'weigh_in:daily', :now, :now)
            ON CONFLICT ON CONSTRAINT uq_daily_task_dedup DO NOTHING
            """
        )
        await connection.execute(statement, parameters)
        await connection.execute(statement, {**parameters, "id": uuid4()})
        task_count = await connection.scalar(
            text("SELECT count(*) FROM daily_tasks WHERE user_id = :user_id"),
            {"user_id": user_id},
        )
        assert task_count == 1
        await connection.execute(
            text("DELETE FROM users WHERE id = :user_id"), {"user_id": user_id}
        )
        cascade_count = await connection.scalar(
            text("SELECT count(*) FROM daily_tasks WHERE user_id = :user_id"),
            {"user_id": user_id},
        )
        assert cascade_count == 0
    await engine.dispose()
