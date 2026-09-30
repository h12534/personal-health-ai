from datetime import UTC, date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.health_activity import (
    ActivityLog,
    HealthPermissionState,
    HealthSyncState,
    SleepLog,
    StepLog,
)
from app.schemas.health_activity import (
    DailyActivityRead,
    HealthSummaryWrite,
    HealthSyncResult,
    PermissionRead,
    PermissionWrite,
)


class HealthActivityService:
    SOURCE_PRIORITY = {"healthkit": 3, "mock": 2, "manual": 1}

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def daily(self, user_id: UUID, on_date: date | None = None) -> DailyActivityRead:
        reference = on_date or date.today()
        logs = list(
            (
                await self.session.scalars(
                    select(StepLog).where(
                        StepLog.user_id == user_id, StepLog.step_date == reference
                    )
                )
            ).all()
        )
        selected = max(
            logs,
            key=lambda item: self.SOURCE_PRIORITY.get(item.source, 0),
            default=None,
        )
        target = await self._step_target(user_id, reference)
        steps = selected.steps if selected else None
        message = (
            "尚无步数数据；这不代表今天走了 0 步。"
            if steps is None
            else f"今日已记录 {steps} 步，目标按近期基线渐进设置为 {target} 步。"
        )
        return DailyActivityRead(
            date=reference,
            steps=steps,
            distance_km=selected.distance_km if selected else None,
            active_energy_kcal=selected.active_energy_kcal if selected else None,
            resting_heart_rate=selected.resting_heart_rate if selected else None,
            source=selected.source if selected else None,
            step_goal=target,
            message=message,
        )

    async def sync_summary(self, user_id: UUID, payload: HealthSummaryWrite) -> HealthSyncResult:
        existing_record = None
        if payload.data_type == "sleep":
            existing_record = await self.session.scalar(
                select(SleepLog).where(
                    SleepLog.user_id == user_id,
                    SleepLog.source == payload.provider,
                    SleepLog.source_record_id == payload.source_record_id,
                )
            )
        elif payload.data_type == "workouts":
            existing_record = await self.session.scalar(
                select(ActivityLog).where(
                    ActivityLog.user_id == user_id,
                    ActivityLog.source == payload.provider,
                    ActivityLog.source_record_id == payload.source_record_id,
                )
            )
        elif payload.data_type in {
            "steps",
            "walking_running_distance",
            "active_energy_burned",
            "resting_heart_rate",
        }:
            existing_record = await self.session.scalar(
                select(StepLog).where(
                    StepLog.user_id == user_id,
                    StepLog.source == payload.provider,
                    StepLog.source_record_id == payload.source_record_id,
                )
            )
        if existing_record is not None:
            await self._update_sync_state(user_id, payload, "success")
            await self.session.commit()
            return HealthSyncResult(
                created=False,
                duplicate=True,
                data_type=payload.data_type,
                source_record_id=payload.source_record_id,
            )

        created = True
        if payload.data_type == "sleep":
            assert payload.sleep_start is not None
            assert payload.sleep_end is not None
            duration = max(0, int((payload.sleep_end - payload.sleep_start).total_seconds() / 60))
            self.session.add(
                SleepLog(
                    user_id=user_id,
                    sleep_start=payload.sleep_start,
                    sleep_end=payload.sleep_end,
                    duration_min=duration,
                    source=payload.provider,
                    sleep_stages=payload.sleep_stages,
                    quality=payload.sleep_quality,
                    source_record_id=payload.source_record_id,
                )
            )
        elif payload.data_type == "workouts":
            assert payload.workout_start is not None
            assert payload.workout_end is not None
            self.session.add(
                ActivityLog(
                    user_id=user_id,
                    activity_date=payload.workout_start.date(),
                    activity_type=payload.workout_type or "other",
                    started_at=payload.workout_start,
                    ended_at=payload.workout_end,
                    duration_min=max(
                        0,
                        int((payload.workout_end - payload.workout_start).total_seconds() / 60),
                    ),
                    source=payload.provider,
                    source_record_id=payload.source_record_id,
                )
            )
        elif payload.data_type in {
            "steps",
            "walking_running_distance",
            "active_energy_burned",
            "resting_heart_rate",
        }:
            reference = payload.recorded_date or date.today()
            existing_day = await self.session.scalar(
                select(StepLog).where(
                    StepLog.user_id == user_id,
                    StepLog.step_date == reference,
                    StepLog.source == payload.provider,
                )
            )
            if existing_day is None:
                existing_day = StepLog(
                    user_id=user_id,
                    step_date=reference,
                    source=payload.provider,
                    source_record_id=payload.source_record_id,
                )
                self.session.add(existing_day)
            else:
                created = False
                existing_day.source_record_id = payload.source_record_id
            if payload.steps is not None:
                existing_day.steps = payload.steps
            if payload.distance_km is not None:
                existing_day.distance_km = payload.distance_km
            if payload.active_energy_kcal is not None:
                existing_day.active_energy_kcal = payload.active_energy_kcal
            if payload.resting_heart_rate is not None:
                existing_day.resting_heart_rate = payload.resting_heart_rate
        await self._update_sync_state(user_id, payload, "success")
        await self.session.commit()
        return HealthSyncResult(
            created=created,
            duplicate=False,
            data_type=payload.data_type,
            source_record_id=payload.source_record_id,
        )

    async def sleep(
        self, user_id: UUID, date_from: date | None = None, date_to: date | None = None
    ) -> list[SleepLog]:
        statement = select(SleepLog).where(SleepLog.user_id == user_id)
        if date_from:
            statement = statement.where(
                SleepLog.sleep_end >= datetime.combine(date_from, datetime.min.time(), UTC)
            )
        if date_to:
            statement = statement.where(
                SleepLog.sleep_start
                < datetime.combine(date_to + timedelta(days=1), datetime.min.time(), UTC)
            )
        return list(
            (await self.session.scalars(statement.order_by(SleepLog.sleep_start.desc()))).all()
        )

    async def set_permission(self, user_id: UUID, payload: PermissionWrite) -> PermissionRead:
        state = await self.session.scalar(
            select(HealthPermissionState).where(
                HealthPermissionState.user_id == user_id,
                HealthPermissionState.provider == "healthkit",
                HealthPermissionState.data_type == payload.data_type,
            )
        )
        now = datetime.now(UTC)
        if state is None:
            state = HealthPermissionState(
                user_id=user_id,
                provider="healthkit",
                data_type=payload.data_type,
                enabled=payload.enabled,
                authorization_status=payload.authorization_status,
                requested_at=now if payload.authorization_status != "not_requested" else None,
            )
            self.session.add(state)
        else:
            state.enabled = payload.enabled
            state.authorization_status = payload.authorization_status
            if payload.authorization_status != "not_requested":
                state.requested_at = now
        await self.session.commit()
        return PermissionRead(
            data_type=state.data_type,
            enabled=state.enabled,
            authorization_status=state.authorization_status,
            requested_at=state.requested_at,
        )

    async def permissions(self, user_id: UUID) -> list[PermissionRead]:
        states = {
            item.data_type: item
            for item in (
                await self.session.scalars(
                    select(HealthPermissionState).where(
                        HealthPermissionState.user_id == user_id,
                        HealthPermissionState.provider == "healthkit",
                    )
                )
            ).all()
        }
        result: list[PermissionRead] = []
        for data_type in ("steps", "sleep", "resting_heart_rate", "workouts"):
            state = states.get(data_type)
            result.append(
                PermissionRead(
                    data_type=data_type,
                    enabled=state.enabled if state else False,
                    authorization_status=(state.authorization_status if state else "not_requested"),
                    requested_at=state.requested_at if state else None,
                )
            )
        return result

    async def delete_provider_data(self, user_id: UUID, provider: str) -> None:
        await self.session.execute(
            delete(StepLog).where(StepLog.user_id == user_id, StepLog.source == provider)
        )
        await self.session.execute(
            delete(SleepLog).where(SleepLog.user_id == user_id, SleepLog.source == provider)
        )
        await self.session.execute(
            delete(ActivityLog).where(
                ActivityLog.user_id == user_id, ActivityLog.source == provider
            )
        )
        await self.session.execute(
            delete(HealthSyncState).where(
                HealthSyncState.user_id == user_id, HealthSyncState.provider == provider
            )
        )
        await self.session.commit()

    async def _step_target(self, user_id: UUID, reference: date) -> int:
        since = reference - timedelta(days=14)
        average = await self.session.scalar(
            select(func.avg(StepLog.steps)).where(
                StepLog.user_id == user_id,
                StepLog.step_date >= since,
                StepLog.step_date < reference,
                StepLog.steps.is_not(None),
            )
        )
        if average is None:
            return 5000
        baseline = Decimal(str(average))
        increase = Decimal("500") if baseline < Decimal("7000") else Decimal("750")
        raw = min(Decimal("12000"), baseline + increase)
        return int(
            (raw / Decimal("500")).quantize(Decimal("1"), rounding=ROUND_HALF_UP) * Decimal("500")
        )

    async def _update_sync_state(
        self, user_id: UUID, payload: HealthSummaryWrite, status: str
    ) -> None:
        state = await self.session.scalar(
            select(HealthSyncState).where(
                HealthSyncState.user_id == user_id,
                HealthSyncState.provider == payload.provider,
                HealthSyncState.data_type == payload.data_type,
            )
        )
        if state is None:
            state = HealthSyncState(
                user_id=user_id,
                provider=payload.provider,
                data_type=payload.data_type,
            )
            self.session.add(state)
        state.last_sync_at = datetime.now(UTC)
        state.cursor = payload.cursor or payload.source_record_id
        state.status = status
        state.error_summary = None
