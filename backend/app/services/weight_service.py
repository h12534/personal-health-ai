from datetime import UTC, date, datetime, timedelta
from statistics import fmean
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.weight_log import WeightLog
from app.repositories.weight_repository import WeightRepository
from app.schemas.weight import (
    WeightCreate,
    WeightTrendPoint,
    WeightTrendSummary,
    WeightUpdate,
)


class WeightService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repository = WeightRepository(session)

    async def create(self, user_id: UUID, payload: WeightCreate) -> WeightLog:
        existing = await self.repository.by_date_including_deleted(user_id, payload.measured_on)
        if existing is not None:
            if existing.deleted_at is None:
                raise AppError(
                    "weight_already_exists", "A weight entry already exists for this date.", 409
                )
            for field, value in payload.model_dump().items():
                setattr(existing, field, value)
            existing.deleted_at = None
            log = existing
        else:
            log = WeightLog(user_id=user_id, **payload.model_dump())
            await self.repository.add(log)
        await self.session.commit()
        await self.session.refresh(log)
        return log

    async def update(self, user_id: UUID, log_id: UUID, payload: WeightUpdate) -> WeightLog:
        log = await self._get_owned(user_id, log_id)
        values = payload.model_dump(exclude_unset=True)
        new_date = values.get("measured_on")
        if new_date is not None and new_date != log.measured_on:
            duplicate = await self.repository.by_date(user_id, new_date)
            if duplicate is not None:
                raise AppError(
                    "weight_already_exists", "A weight entry already exists for this date.", 409
                )
        for field, value in values.items():
            setattr(log, field, value)
        await self.session.commit()
        await self.session.refresh(log)
        return log

    async def delete(self, user_id: UUID, log_id: UUID) -> None:
        log = await self._get_owned(user_id, log_id)
        log.deleted_at = datetime.now(UTC)
        await self.session.commit()

    async def _get_owned(self, user_id: UUID, log_id: UUID) -> WeightLog:
        log = await self.repository.by_id(user_id, log_id)
        if log is None:
            raise AppError("weight_not_found", "Weight entry was not found.", 404)
        return log


def build_weight_trend(logs: list[WeightLog], today: date | None = None) -> WeightTrendSummary:
    if not logs:
        return WeightTrendSummary(
            points=[],
            latest_weight_kg=None,
            average_7d_kg=None,
            previous_7d_average_kg=None,
            week_change_kg=None,
            rate_kg_per_week=None,
        )

    ordered = sorted(logs, key=lambda item: item.measured_on)
    points: list[WeightTrendPoint] = []
    for current in ordered:
        window_start = current.measured_on - timedelta(days=6)
        window = [
            float(x.weight_kg)
            for x in ordered
            if window_start <= x.measured_on <= current.measured_on
        ]
        points.append(
            WeightTrendPoint(
                measured_on=current.measured_on,
                weight_kg=float(current.weight_kg),
                moving_average_7d=round(fmean(window), 2),
            )
        )

    reference = today or date.today()
    current_values = [
        float(x.weight_kg)
        for x in ordered
        if reference - timedelta(days=6) <= x.measured_on <= reference
    ]
    previous_values = [
        float(x.weight_kg)
        for x in ordered
        if reference - timedelta(days=13) <= x.measured_on <= reference - timedelta(days=7)
    ]
    current_average = round(fmean(current_values), 2) if current_values else None
    previous_average = round(fmean(previous_values), 2) if previous_values else None
    week_change = (
        round(current_average - previous_average, 2)
        if current_average is not None and previous_average is not None
        else None
    )
    return WeightTrendSummary(
        points=points,
        latest_weight_kg=float(ordered[-1].weight_kg),
        average_7d_kg=current_average,
        previous_7d_average_kg=previous_average,
        week_change_kg=week_change,
        rate_kg_per_week=week_change,
    )
