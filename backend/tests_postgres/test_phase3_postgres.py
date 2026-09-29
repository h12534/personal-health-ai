import os
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from redis.asyncio import Redis
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.models.meal_analysis import MealAnalysisSession, MealImage
from app.models.user import User

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_phase3_migration_uses_postgres_jsonb_and_required_tables() -> None:
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
            "meal_images",
            "meal_analysis_sessions",
            "meal_analysis_items",
            "personal_food_memories",
            "ai_usage_logs",
        } <= tables
        json_types = set(
            (
                await connection.scalars(
                    text(
                        "SELECT data_type FROM information_schema.columns "
                        "WHERE table_name IN ('meal_analysis_sessions', 'meal_analysis_items') "
                        "AND column_name IN "
                        "('warnings', 'raw_provider_response', 'visible_components')"
                    )
                )
            ).all()
        )
        assert json_types == {"jsonb"}
        constraint = await connection.scalar(
            text(
                "SELECT constraint_name FROM information_schema.table_constraints "
                "WHERE table_name = 'meal_analysis_sessions' "
                "AND constraint_name = 'uq_analysis_user_idempotency'"
            )
        )
        assert constraint == "uq_analysis_user_idempotency"
    await engine.dispose()


@pytest.mark.asyncio
async def test_phase3_worker_redis_is_available() -> None:
    redis = Redis.from_url(os.environ["REDIS_URL"])
    try:
        assert await redis.ping() is True
    finally:
        await redis.aclose()


@pytest.mark.asyncio
async def test_phase3_postgres_uuid_timezone_and_jsonb_round_trip() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    async with sessions() as session:
        transaction = await session.begin()
        now = datetime.now(UTC).replace(microsecond=0)
        user = User(
            email="phase3-postgres@example.net",
            password_hash="integration-test-only",
        )
        session.add(user)
        await session.flush()
        image = MealImage(
            user_id=user.id,
            object_key=f"meal-analysis/integration/{user.id}.jpg",
            content_type="image/jpeg",
            size_bytes=1234,
            width=640,
            height=480,
            sha256="a" * 64,
            retention_expires_at=now + timedelta(days=30),
        )
        analysis = MealAnalysisSession(
            user_id=user.id,
            image=image,
            status="completed",
            provider="mock",
            model="postgres-integration",
            prompt_version="meal_v1",
            idempotency_key=f"postgres-{user.id}",
            meal_type="lunch",
            overall_confidence=0.82,
            warnings=["份量需要确认"],
            raw_provider_response={"nested": {"foods": ["米饭", "青菜"]}},
            expires_at=now + timedelta(hours=24),
        )
        session.add(analysis)
        await session.flush()
        analysis_id = analysis.id
        session.expunge_all()

        loaded = await session.scalar(
            select(MealAnalysisSession).where(MealAnalysisSession.id == analysis_id)
        )
        assert loaded is not None
        assert isinstance(loaded.id, UUID)
        assert loaded.expires_at.tzinfo is not None
        assert loaded.warnings == ["份量需要确认"]
        assert loaded.raw_provider_response == {"nested": {"foods": ["米饭", "青菜"]}}
        await transaction.rollback()
    await engine.dispose()
