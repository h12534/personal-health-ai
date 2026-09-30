from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.health_knowledge import HealthCheckSuggestion, LabReport


class HealthCheckRecommendationService:
    FOLLOW_UP_DAYS = {
        "HBA1C": 90,
        "FASTING_GLUCOSE": 90,
        "TOTAL_CHOLESTEROL": 90,
        "LDL_C": 90,
        "TRIGLYCERIDES": 90,
        "ALT": 90,
        "AST": 90,
        "GGT": 90,
        "URIC_ACID": 90,
    }

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def generate(self, user_id: UUID, report_id: UUID) -> list[HealthCheckSuggestion]:
        report = await self.session.scalar(
            select(LabReport).where(
                LabReport.id == report_id,
                LabReport.user_id == user_id,
                LabReport.deleted_at.is_(None),
                LabReport.review_status == "confirmed",
            )
        )
        if report is None:
            raise AppError("lab_report_not_found", "Confirmed lab report was not found.", 404)
        existing = list(
            (
                await self.session.scalars(
                    select(HealthCheckSuggestion).where(
                        HealthCheckSuggestion.user_id == user_id,
                        HealthCheckSuggestion.report_id == report_id,
                    )
                )
            ).all()
        )
        if existing:
            return existing
        values: list[HealthCheckSuggestion] = []
        for result in report.results:
            if result.deleted_at is not None or result.flag not in {"low", "high"}:
                continue
            days = self.FOLLOW_UP_DAYS.get(result.normalized_name, 180)
            values.append(
                HealthCheckSuggestion(
                    user_id=user_id,
                    report_id=report.id,
                    suggestion_type="lab_follow_up",
                    description=(
                        f"{result.test_name} 本次报告标记为{result.flag}。可与医生讨论是否在约 "
                        f"{days // 30} 个月后复查；这不是自动医疗安排。"
                    ),
                    suggested_after_days=days,
                    evidence_snapshot={
                        "lab_result_id": str(result.id),
                        "flag": result.flag,
                        "report_reference": result.reference_text,
                    },
                    status="suggested",
                )
            )
        self.session.add_all(values)
        await self.session.commit()
        return values

    async def accept(self, user_id: UUID, suggestion_id: UUID) -> HealthCheckSuggestion:
        value = await self.session.scalar(
            select(HealthCheckSuggestion).where(
                HealthCheckSuggestion.id == suggestion_id,
                HealthCheckSuggestion.user_id == user_id,
            )
        )
        if value is None:
            raise AppError("health_check_suggestion_not_found", "Suggestion was not found.", 404)
        value.status = "accepted"
        value.accepted_at = datetime.now(UTC)
        await self.session.commit()
        return value
