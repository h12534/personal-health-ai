from collections import defaultdict
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Literal, cast
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import AppError
from app.models.training import (
    Exercise,
    ExercisePR,
    PainLog,
    WorkoutSession,
    WorkoutSet,
)
from app.schemas.training import (
    ExerciseProgressRead,
    PainLogWrite,
    ProgressPoint,
    PRRead,
    WorkoutComplete,
    WorkoutSessionCreate,
    WorkoutSessionRead,
    WorkoutSetCreate,
    WorkoutSetUpdate,
    WorkoutSummary,
)
from app.services.training_metrics import estimate_one_rep_max, volume_load

WORKOUT_LOAD = selectinload(WorkoutSession.sets)


class WorkoutService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(
        self, user_id: UUID, payload: WorkoutSessionCreate, idempotency_key: str | None
    ) -> WorkoutSession:
        key = (
            payload.idempotency_key
            or idempotency_key
            or (str(payload.id) if payload.id is not None else None)
        )
        if key:
            existing = await self.session.scalar(
                select(WorkoutSession)
                .where(
                    WorkoutSession.user_id == user_id,
                    WorkoutSession.idempotency_key == key,
                )
                .options(WORKOUT_LOAD)
            )
            if existing:
                return existing
        values = payload.model_dump(exclude={"id", "idempotency_key", "started_at"})
        session = WorkoutSession(
            **values,
            id=payload.id,
            user_id=user_id,
            started_at=payload.started_at or datetime.now(UTC),
            status="in_progress",
            idempotency_key=key,
        )
        self.session.add(session)
        await self.session.commit()
        return await self.get(user_id, session.id)

    async def list_all(
        self, user_id: UUID, date_from: date | None = None, date_to: date | None = None
    ) -> list[WorkoutSession]:
        statement = select(WorkoutSession).where(WorkoutSession.user_id == user_id)
        if date_from:
            statement = statement.where(
                WorkoutSession.started_at >= datetime.combine(date_from, datetime.min.time(), UTC)
            )
        if date_to:
            statement = statement.where(
                WorkoutSession.started_at
                < datetime.combine(date_to + timedelta(days=1), datetime.min.time(), UTC)
            )
        statement = statement.options(WORKOUT_LOAD).order_by(WorkoutSession.started_at.desc())
        sessions = list((await self.session.scalars(statement)).unique().all())
        for workout in sessions:
            workout.sets.sort(key=lambda item: (item.created_at, item.set_number))
        return sessions

    async def get(self, user_id: UUID, session_id: UUID) -> WorkoutSession:
        statement = (
            select(WorkoutSession)
            .where(WorkoutSession.id == session_id, WorkoutSession.user_id == user_id)
            .options(WORKOUT_LOAD)
        )
        workout = (await self.session.scalars(statement)).unique().one_or_none()
        if workout is None:
            raise AppError("workout_not_found", "Workout session was not found.", 404)
        workout.sets.sort(key=lambda item: (item.created_at, item.set_number))
        return workout

    async def add_set(
        self,
        user_id: UUID,
        session_id: UUID,
        payload: WorkoutSetCreate,
        idempotency_key: str | None,
    ) -> WorkoutSet:
        workout = await self.get(user_id, session_id)
        if workout.status == "completed":
            raise AppError("workout_completed", "Completed workouts cannot accept new sets.", 409)
        key = (
            payload.idempotency_key
            or idempotency_key
            or (str(payload.id) if payload.id is not None else None)
        )
        if payload.id is not None:
            existing_by_id = await self.session.get(WorkoutSet, payload.id)
            if existing_by_id is not None:
                if existing_by_id.session_id != session_id:
                    raise AppError("set_id_conflict", "Set UUID belongs to another workout.", 409)
                return existing_by_id
        if key:
            existing = await self.session.scalar(
                select(WorkoutSet).where(
                    WorkoutSet.session_id == session_id,
                    WorkoutSet.idempotency_key == key,
                )
            )
            if existing:
                return existing
        values = payload.model_dump(exclude={"id", "idempotency_key", "rpe", "rir"})
        rpe, rir = self._effort(payload.rpe, payload.rir)
        workout_set = WorkoutSet(
            **values,
            id=payload.id,
            session_id=session_id,
            rpe=rpe,
            rir=rir,
            idempotency_key=key,
        )
        self.session.add(workout_set)
        await self.session.commit()
        await self.session.refresh(workout_set)
        return workout_set

    async def update_set(
        self,
        user_id: UUID,
        session_id: UUID,
        set_id: UUID,
        payload: WorkoutSetUpdate,
    ) -> WorkoutSet:
        await self.get(user_id, session_id)
        workout_set = await self.session.scalar(
            select(WorkoutSet).where(WorkoutSet.id == set_id, WorkoutSet.session_id == session_id)
        )
        if workout_set is None:
            raise AppError("workout_set_not_found", "Workout set was not found.", 404)
        values = payload.model_dump(exclude_unset=True)
        for field, value in values.items():
            setattr(workout_set, field, value)
        if "rpe" in values or "rir" in values:
            workout_set.rpe, workout_set.rir = self._effort(values.get("rpe"), values.get("rir"))
        await self.session.commit()
        await self.session.refresh(workout_set)
        return workout_set

    async def complete(
        self, user_id: UUID, session_id: UUID, payload: WorkoutComplete
    ) -> WorkoutSummary:
        workout = await self.get(user_id, session_id)
        ended_at = payload.ended_at or datetime.now(UTC)
        workout.ended_at = ended_at
        normalized_end = ended_at if ended_at.tzinfo is not None else ended_at.replace(tzinfo=UTC)
        normalized_start = (
            workout.started_at
            if workout.started_at.tzinfo is not None
            else workout.started_at.replace(tzinfo=UTC)
        )
        workout.duration_min = max(0, int((normalized_end - normalized_start).total_seconds() / 60))
        workout.status = "completed"
        workout.session_rpe = payload.session_rpe
        workout.energy_level = payload.energy_level or workout.energy_level
        if payload.notes is not None:
            workout.notes = payload.notes
        prs = await self._update_prs(user_id, workout)
        await self.session.commit()
        completed = await self.get(user_id, session_id)
        effective = [
            item for item in completed.sets if item.completed and item.set_type != "warmup"
        ]
        total_volume = sum(
            (
                volume_load(item.weight_kg, item.reps, item.set_type, item.completed)
                for item in completed.sets
            ),
            Decimal("0"),
        )
        return WorkoutSummary(
            session=WorkoutSessionRead.model_validate(completed),
            total_sets=len(completed.sets),
            effective_sets=len(effective),
            volume_load=total_volume,
            prs=[PRRead.model_validate(item) for item in prs],
            message=(
                f"本次完成 {len(effective)} 个有效组。"
                + (f"检测到 {len(prs)} 项个人纪录。" if prs else "按计划稳步积累即可。")
            ),
        )

    async def progress(
        self, user_id: UUID, exercise_id: UUID, period_days: int = 28
    ) -> ExerciseProgressRead:
        since = datetime.now(UTC) - timedelta(days=period_days)
        statement = (
            select(WorkoutSet, WorkoutSession.started_at)
            .join(WorkoutSession, WorkoutSet.session_id == WorkoutSession.id)
            .where(
                WorkoutSession.user_id == user_id,
                WorkoutSession.status == "completed",
                WorkoutSession.started_at >= since,
                WorkoutSet.exercise_id == exercise_id,
                WorkoutSet.completed.is_(True),
                WorkoutSet.set_type != "warmup",
            )
            .order_by(WorkoutSession.started_at)
        )
        rows = (await self.session.execute(statement)).all()
        daily: dict[date, list[WorkoutSet]] = defaultdict(list)
        for workout_set, started_at in rows:
            daily[started_at.date()].append(workout_set)
        points: list[ProgressPoint] = []
        for on_date, sets in sorted(daily.items()):
            estimates = [estimate_one_rep_max(item.weight_kg, item.reps) for item in sets]
            best_index = max(range(len(estimates)), key=lambda index: estimates[index].estimate)
            best = estimates[best_index]
            points.append(
                ProgressPoint(
                    date=on_date,
                    max_weight_kg=max(item.weight_kg for item in sets),
                    max_reps=max(item.reps for item in sets),
                    estimated_1rm_kg=best.estimate,
                    volume_load=sum(
                        (volume_load(item.weight_kg, item.reps, item.set_type) for item in sets),
                        Decimal("0"),
                    ),
                    e1rm_confidence=cast(Literal["high", "normal", "low"], best.confidence),
                )
            )
        return ExerciseProgressRead(exercise_id=exercise_id, period_days=period_days, points=points)

    async def prs(self, user_id: UUID) -> list[ExercisePR]:
        statement = (
            select(ExercisePR)
            .where(ExercisePR.user_id == user_id)
            .order_by(ExercisePR.achieved_at.desc())
        )
        return list((await self.session.scalars(statement)).all())

    async def log_pain(self, user_id: UUID, payload: PainLogWrite) -> PainLog:
        if payload.workout_session_id:
            await self.get(user_id, payload.workout_session_id)
        pain = PainLog(user_id=user_id, **payload.model_dump())
        self.session.add(pain)
        await self.session.commit()
        await self.session.refresh(pain)
        return pain

    async def _update_prs(self, user_id: UUID, workout: WorkoutSession) -> list[ExercisePR]:
        effective = [
            item
            for item in workout.sets
            if item.completed and item.set_type != "warmup" and item.reps > 0
        ]
        by_exercise: dict[UUID, list[WorkoutSet]] = defaultdict(list)
        for item in effective:
            by_exercise[item.exercise_id].append(item)
        changed: list[ExercisePR] = []
        for exercise_id, sets in by_exercise.items():
            candidates: dict[str, tuple[Decimal, WorkoutSet, str]] = {}
            max_weight = max(sets, key=lambda item: item.weight_kg)
            max_reps = max(sets, key=lambda item: item.reps)
            max_volume = max(sets, key=lambda item: item.weight_kg * item.reps)
            best_e1rm_set = max(
                sets,
                key=lambda item: estimate_one_rep_max(item.weight_kg, item.reps).estimate,
            )
            one_rm = estimate_one_rep_max(best_e1rm_set.weight_kg, best_e1rm_set.reps)
            candidates["max_weight"] = (max_weight.weight_kg, max_weight, "normal")
            candidates["max_reps"] = (Decimal(max_reps.reps), max_reps, "normal")
            candidates["volume"] = (
                volume_load(max_volume.weight_kg, max_volume.reps, max_volume.set_type),
                max_volume,
                "normal",
            )
            candidates["estimated_1rm"] = (
                one_rm.estimate,
                best_e1rm_set,
                one_rm.confidence,
            )
            for pr_type, (value, source_set, confidence) in candidates.items():
                existing = await self.session.scalar(
                    select(ExercisePR).where(
                        ExercisePR.user_id == user_id,
                        ExercisePR.exercise_id == exercise_id,
                        ExercisePR.pr_type == pr_type,
                    )
                )
                if existing is None:
                    existing = ExercisePR(
                        user_id=user_id,
                        exercise_id=exercise_id,
                        pr_type=pr_type,
                        value=value,
                        workout_set_id=source_set.id,
                        achieved_at=workout.ended_at or datetime.now(UTC),
                        confidence=confidence,
                    )
                    self.session.add(existing)
                    changed.append(existing)
                elif value > existing.value:
                    existing.value = value
                    existing.workout_set_id = source_set.id
                    existing.achieved_at = workout.ended_at or datetime.now(UTC)
                    existing.confidence = confidence
                    changed.append(existing)
        await self.session.flush()
        return changed

    @staticmethod
    def _effort(rpe: Decimal | None, rir: Decimal | None) -> tuple[Decimal | None, Decimal | None]:
        if rpe is None and rir is not None:
            rpe = max(Decimal("1"), Decimal("10") - rir)
        if rir is None and rpe is not None:
            rir = max(Decimal("0"), Decimal("10") - rpe)
        return rpe, rir


class WeightSuggestionService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def recent_sets(
        self, user_id: UUID, exercise_id: UUID, limit_sessions: int = 5
    ) -> list[dict[str, object]]:
        statement = (
            select(WorkoutSet, WorkoutSession.started_at, Exercise.movement_pattern)
            .join(WorkoutSession, WorkoutSet.session_id == WorkoutSession.id)
            .join(Exercise, WorkoutSet.exercise_id == Exercise.id)
            .where(
                WorkoutSession.user_id == user_id,
                WorkoutSession.status == "completed",
                WorkoutSet.exercise_id == exercise_id,
                WorkoutSet.completed.is_(True),
                WorkoutSet.set_type != "warmup",
            )
            .order_by(WorkoutSession.started_at.desc())
            .limit(limit_sessions * 6)
        )
        rows = (await self.session.execute(statement)).all()
        return [
            {
                "date": started_at.isoformat(),
                "weight_kg": str(workout_set.weight_kg),
                "reps": workout_set.reps,
                "rir": str(workout_set.rir) if workout_set.rir is not None else None,
                "rpe": str(workout_set.rpe) if workout_set.rpe is not None else None,
                "movement_pattern": movement_pattern,
            }
            for workout_set, started_at, movement_pattern in rows
        ]
