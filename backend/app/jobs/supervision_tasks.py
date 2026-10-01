import asyncio
from datetime import UTC, datetime

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import Settings, get_settings
from app.jobs.celery_app import celery_app
from app.models.user import User
from app.providers.ai import build_health_answer_provider
from app.providers.push import build_push_provider
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.daily_task_service import DailyTaskEngine, ReminderPreferenceService
from app.services.health_report_service import HealthReportService, ProactiveCoachService
from app.services.reminder_service import NotificationService, ReminderEngine

logger = structlog.get_logger()


def _runtime() -> tuple[Settings, AsyncEngine, async_sessionmaker[AsyncSession]]:
    settings = get_settings()
    connect_args = (
        {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
    )
    engine = create_async_engine(
        settings.database_url, pool_pre_ping=True, connect_args=connect_args
    )
    return settings, engine, async_sessionmaker(engine, expire_on_commit=False, autoflush=False)


async def _supervision_sweep() -> dict[str, int]:
    settings, engine, sessions = _runtime()
    stats = {"users": 0, "tasks": 0, "notifications": 0, "reports": 0}
    try:
        async with sessions() as session:
            users = list(
                (await session.scalars(select(User).where(User.is_active.is_(True)))).all()
            )
            for user in users:
                stats["users"] += 1
                timezone = await DailyNutritionService(session).timezone(user.id)
                local_now = datetime.now(UTC).astimezone(timezone)
                tasks = await DailyTaskEngine(session).generate(user.id, local_now.date())
                stats["tasks"] += len(tasks)
                preference = await ReminderPreferenceService(session).get(user.id)
                reminder = ReminderEngine(session)
                sender = NotificationService(session, build_push_provider(settings))
                if preference.server_notifications_enabled:
                    for task in tasks:
                        decision = await reminder.decide(task, preference)
                        if decision.should_send and decision.channel == "server":
                            log = await sender.send(task, decision)
                            stats["notifications"] += log.status == "sent"
                await ProactiveCoachService(session, settings).evaluate(user.id, local_now.date())
                reports = HealthReportService(
                    session, build_health_answer_provider(settings), settings
                )
                if (local_now.hour, local_now.minute) >= (21, 30):
                    await reports.generate(user.id, "daily", local_now.date())
                    stats["reports"] += 1
                if local_now.weekday() == preference.weekly_report_day and local_now.hour >= 20:
                    await reports.generate(user.id, "weekly", local_now.date())
                    stats["reports"] += 1
                if local_now.day == preference.monthly_report_day and local_now.hour >= 20:
                    await reports.generate(user.id, "monthly", local_now.date())
                    stats["reports"] += 1
        logger.info("supervision_sweep_completed", **stats)
        return stats
    finally:
        await engine.dispose()


@celery_app.task(name="supervision.sweep")  # type: ignore[untyped-decorator]
def supervision_sweep() -> dict[str, int]:
    return asyncio.run(_supervision_sweep())
