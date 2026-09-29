import asyncio
from uuid import UUID

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import Settings, get_settings
from app.jobs.celery_app import celery_app
from app.providers.ai import build_vision_provider
from app.providers.storage.local import LocalStorageProvider
from app.services.meal_analysis_service import MealAnalysisService


def _task_runtime() -> tuple[Settings, AsyncEngine, async_sessionmaker[AsyncSession]]:
    settings = get_settings()
    connect_args = (
        {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
    )
    engine = create_async_engine(
        settings.database_url,
        pool_pre_ping=True,
        connect_args=connect_args,
    )
    sessions = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)
    return settings, engine, sessions


async def _process(analysis_id: str) -> None:
    settings, engine, sessions = _task_runtime()
    try:
        async with sessions() as session:
            service = MealAnalysisService(
                session,
                settings,
                build_vision_provider(settings),
                LocalStorageProvider(settings.upload_dir),
            )
            await service.process(UUID(analysis_id))
    finally:
        await engine.dispose()


@celery_app.task(name="meal_analysis.process", autoretry_for=(), max_retries=0)
def process_meal_analysis(analysis_id: str) -> None:
    asyncio.run(_process(analysis_id))


async def _cleanup() -> tuple[int, int]:
    settings, engine, sessions = _task_runtime()
    try:
        async with sessions() as session:
            service = MealAnalysisService(
                session,
                settings,
                build_vision_provider(settings),
                LocalStorageProvider(settings.upload_dir),
            )
            return await service.cleanup_expired()
    finally:
        await engine.dispose()


@celery_app.task(name="meal_analysis.cleanup_expired")
def cleanup_expired_meal_analyses() -> tuple[int, int]:
    return asyncio.run(_cleanup())
