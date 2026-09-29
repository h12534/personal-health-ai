from celery import Celery  # type: ignore[import-untyped]

from app.core.config import get_settings

settings = get_settings()
celery_app = Celery(
    "health_os",
    broker=settings.redis_url,
    backend=settings.redis_url,
    include=["app.jobs.meal_analysis_tasks"],
)
celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    beat_schedule={
        "cleanup-expired-meal-analyses-daily": {
            "task": "meal_analysis.cleanup_expired",
            "schedule": 86400.0,
        }
    },
)
