"""Seed deterministic, non-sensitive records for the PostgreSQL restore drill."""

import asyncio
import json
from datetime import UTC, date, datetime, time
from decimal import Decimal
from uuid import UUID

from sqlalchemy import delete

from app.db.session import SessionLocal
from app.models.health_knowledge import (
    KnowledgeChunk,
    KnowledgeDocument,
    LabReport,
    LabResult,
)
from app.models.meal import MealLog
from app.models.supervision import DailyTask, HealthReport
from app.models.training import WorkoutSession
from app.models.user import User
from app.models.weight_log import WeightLog

MARKER_EMAIL = "rc-restore-drill@example.invalid"
MARKER_DOCUMENT_TITLE = "RC restore drill knowledge document"


async def seed() -> dict[str, str]:
    now = datetime.now(UTC)
    ids = {
        "user": UUID("7c000000-0000-4000-8000-000000000001"),
        "weight": UUID("7c000000-0000-4000-8000-000000000002"),
        "meal": UUID("7c000000-0000-4000-8000-000000000003"),
        "workout": UUID("7c000000-0000-4000-8000-000000000004"),
        "knowledge_document": UUID("7c000000-0000-4000-8000-000000000005"),
        "knowledge_chunk": UUID("7c000000-0000-4000-8000-000000000006"),
        "lab_report": UUID("7c000000-0000-4000-8000-000000000007"),
        "lab_result": UUID("7c000000-0000-4000-8000-000000000008"),
        "daily_task": UUID("7c000000-0000-4000-8000-000000000009"),
        "health_report": UUID("7c000000-0000-4000-8000-000000000010"),
    }
    async with SessionLocal() as session:
        await session.execute(delete(User).where(User.email == MARKER_EMAIL))
        await session.execute(
            delete(KnowledgeDocument).where(KnowledgeDocument.title == MARKER_DOCUMENT_TITLE)
        )
        await session.flush()

        user = User(
            id=ids["user"],
            email=MARKER_EMAIL,
            password_hash="restore-drill-placeholder-not-a-login-secret",
            is_active=False,
            is_superuser=False,
        )
        session.add(user)
        # Use an explicit flush because these restore fixtures intentionally use
        # scalar foreign-key IDs instead of ORM relationships.
        await session.flush()
        session.add_all(
            [
                WeightLog(
                    id=ids["weight"],
                    user_id=user.id,
                    measured_on=date(2026, 10, 1),
                    weight_kg=Decimal("98.40"),
                    source="restore_drill",
                ),
                MealLog(
                    id=ids["meal"],
                    user_id=user.id,
                    meal_type="lunch",
                    eaten_at=datetime(2026, 10, 1, 4, 0, tzinfo=UTC),
                    source="restore_drill",
                    idempotency_key="rc-restore-meal",
                    total_calories=Decimal("620"),
                    total_protein=Decimal("38"),
                    total_carbs=Decimal("72"),
                    total_fat=Decimal("20"),
                    total_fiber=Decimal("9"),
                ),
                WorkoutSession(
                    id=ids["workout"],
                    user_id=user.id,
                    started_at=datetime(2026, 10, 1, 10, 0, tzinfo=UTC),
                    ended_at=datetime(2026, 10, 1, 10, 45, tzinfo=UTC),
                    duration_min=45,
                    status="completed",
                    source="restore_drill",
                    idempotency_key="rc-restore-workout",
                ),
                LabReport(
                    id=ids["lab_report"],
                    user_id=user.id,
                    report_date=date(2026, 9, 30),
                    source_type="text_pdf",
                    original_filename="restore-drill.txt",
                    content_type="text/plain",
                    size_bytes=24,
                    sha256="0" * 64,
                    ocr_status="completed",
                    review_status="confirmed",
                    retain_original=False,
                ),
                DailyTask(
                    id=ids["daily_task"],
                    user_id=user.id,
                    task_date=date(2026, 10, 1),
                    task_type="weigh_in",
                    title="Restore drill task",
                    description="Synthetic release-candidate record",
                    status="completed",
                    priority=100,
                    scheduled_time=time(8),
                    completed_at=now,
                    source="restore_drill",
                    reminder_policy={},
                    dedup_key="rc-restore-task",
                ),
                HealthReport(
                    id=ids["health_report"],
                    user_id=user.id,
                    report_type="daily",
                    period_start=date(2026, 10, 1),
                    period_end=date(2026, 10, 1),
                    metrics_snapshot={"synthetic": True},
                    summary="Synthetic restore drill report.",
                    next_actions=[],
                    rule_version="restore_drill_v1",
                    prompt_version="none",
                    input_snapshot_hash="1" * 64,
                    provider="none",
                    model="none",
                ),
            ]
        )
        document = KnowledgeDocument(
            id=ids["knowledge_document"],
            title=MARKER_DOCUMENT_TITLE,
            source="restore_drill",
            publisher="Local test fixture",
            authors=[],
            document_version="1",
            language="en",
            category="nutrition",
            evidence_level="general_reference",
            document_type="text",
            active=True,
            archived=False,
            checksum="2" * 64,
            content_hash="3" * 64,
            ingested_at=now,
        )
        session.add(document)
        await session.flush()
        session.add(
            KnowledgeChunk(
                id=ids["knowledge_chunk"],
                document_id=document.id,
                chunk_index=0,
                heading="Restore drill",
                content="Synthetic content used only to validate database restoration.",
                token_count=9,
                category="nutrition",
                content_hash="4" * 64,
                embedding=[0.01] * 64,
                embedding_model="restore-drill-64d",
                chunk_metadata={"synthetic": True},
            )
        )
        session.add(
            LabResult(
                id=ids["lab_result"],
                report_id=ids["lab_report"],
                test_code="HBA1C",
                test_name="HbA1c",
                normalized_name="HBA1C",
                value_numeric=Decimal("5.600000"),
                unit="%",
                reference_min=Decimal("4.000000"),
                reference_max=Decimal("6.000000"),
                flag="normal",
                category="glucose",
                confidence=Decimal("1.0000"),
                user_confirmed=True,
            )
        )
        await session.commit()
    return {name: str(value) for name, value in ids.items()}


def main() -> None:
    result = asyncio.run(seed())
    print(json.dumps({"marker_email": MARKER_EMAIL, "ids": result}, sort_keys=True))


if __name__ == "__main__":
    main()
