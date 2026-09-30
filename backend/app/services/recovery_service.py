from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Literal
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.health_activity import RecoverySnapshot, SleepLog, StepLog
from app.models.training import PainLog, WorkoutSession
from app.schemas.health_activity import RecoveryInput, RecoveryRead


class RecoveryRuleEngine:
    VERSION = "recovery_v1"

    @classmethod
    def evaluate(
        cls,
        *,
        sleep_duration_min: int | None,
        fatigue: int | None,
        last_session_rpe: Decimal | None,
        resting_heart_rate: int | None,
        resting_heart_rate_baseline: Decimal | None,
        pain_severity: int | None,
        recent_training_count: int,
    ) -> tuple[Literal["good", "normal", "reduced", "insufficient_data"], list[str]]:
        known = [
            sleep_duration_min is not None,
            fatigue is not None,
            last_session_rpe is not None,
            resting_heart_rate is not None and resting_heart_rate_baseline is not None,
            pain_severity is not None,
        ]
        if sum(known) < 2:
            return "insufficient_data", ["睡眠、疲劳、心率或疼痛数据不足，维持保守判断。"]
        reasons: list[str] = []
        reduced_signals = 0
        good_signals = 0
        if sleep_duration_min is not None:
            if sleep_duration_min < 300:
                reduced_signals += 2
                reasons.append("睡眠少于 5 小时")
            elif sleep_duration_min < 390:
                reduced_signals += 1
                reasons.append("睡眠时间偏短")
            elif sleep_duration_min >= 420:
                good_signals += 1
        if fatigue is not None:
            if fatigue >= 4:
                reduced_signals += 2
                reasons.append("主观疲劳较高")
            elif fatigue <= 2:
                good_signals += 1
        if pain_severity is not None and pain_severity >= 5:
            reduced_signals += 2
            reasons.append("存在中高程度疼痛或不适")
        if last_session_rpe is not None and last_session_rpe >= Decimal("9"):
            reduced_signals += 1
            reasons.append("上次训练主观强度很高")
        if (
            resting_heart_rate is not None
            and resting_heart_rate_baseline is not None
            and Decimal(resting_heart_rate) >= resting_heart_rate_baseline + Decimal("8")
        ):
            reduced_signals += 1
            reasons.append("静息心率高于滚动基线")
        if recent_training_count >= 5:
            reduced_signals += 1
            reasons.append("近 7 天训练频率较高")
        if reduced_signals >= 2:
            return "reduced", reasons
        if good_signals >= 2 and reduced_signals == 0:
            return "good", ["睡眠与主观状态支持按计划训练。"]
        return "normal", reasons or ["当前恢复信号总体普通，可按计划并保留余力。"]


class RecoveryService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def today(self, user_id: UUID, user_input: RecoveryInput | None = None) -> RecoveryRead:
        reference = date.today()
        start = datetime.combine(reference - timedelta(days=1), datetime.min.time(), UTC)
        end = datetime.combine(reference + timedelta(days=1), datetime.min.time(), UTC)
        sleep = await self.session.scalar(
            select(SleepLog)
            .where(
                SleepLog.user_id == user_id,
                SleepLog.sleep_end >= start,
                SleepLog.sleep_end < end,
            )
            .order_by(SleepLog.sleep_end.desc())
        )
        recent_session = await self.session.scalar(
            select(WorkoutSession)
            .where(
                WorkoutSession.user_id == user_id,
                WorkoutSession.status == "completed",
            )
            .order_by(WorkoutSession.ended_at.desc())
        )
        recent_training_count = int(
            await self.session.scalar(
                select(func.count(WorkoutSession.id)).where(
                    WorkoutSession.user_id == user_id,
                    WorkoutSession.status == "completed",
                    WorkoutSession.started_at >= datetime.now(UTC) - timedelta(days=7),
                )
            )
            or 0
        )
        latest_pain = await self.session.scalar(
            select(PainLog)
            .where(
                PainLog.user_id == user_id,
                PainLog.created_at >= datetime.now(UTC) - timedelta(days=7),
            )
            .order_by(PainLog.severity.desc())
        )
        rhr = await self.session.scalar(
            select(StepLog.resting_heart_rate)
            .where(
                StepLog.user_id == user_id,
                StepLog.step_date == reference,
                StepLog.resting_heart_rate.is_not(None),
            )
            .order_by(StepLog.updated_at.desc())
        )
        baseline = await self.session.scalar(
            select(func.avg(StepLog.resting_heart_rate)).where(
                StepLog.user_id == user_id,
                StepLog.step_date >= reference - timedelta(days=28),
                StepLog.step_date < reference,
                StepLog.resting_heart_rate.is_not(None),
            )
        )
        fatigue = user_input.subjective_fatigue if user_input else None
        pain = (
            user_input.pain_severity
            if user_input and user_input.pain_severity is not None
            else latest_pain.severity
            if latest_pain
            else None
        )
        status, reasons = RecoveryRuleEngine.evaluate(
            sleep_duration_min=sleep.duration_min if sleep else None,
            fatigue=fatigue,
            last_session_rpe=recent_session.session_rpe if recent_session else None,
            resting_heart_rate=rhr,
            resting_heart_rate_baseline=Decimal(str(baseline)) if baseline is not None else None,
            pain_severity=pain,
            recent_training_count=recent_training_count,
        )
        snapshot = await self.session.scalar(
            select(RecoverySnapshot).where(
                RecoverySnapshot.user_id == user_id,
                RecoverySnapshot.snapshot_date == reference,
            )
        )
        values: dict[str, object] = {
            "status": status,
            "sleep_duration_min": sleep.duration_min if sleep else None,
            "subjective_fatigue": fatigue,
            "last_session_rpe": recent_session.session_rpe if recent_session else None,
            "resting_heart_rate": rhr,
            "resting_heart_rate_baseline": (
                Decimal(str(baseline)) if baseline is not None else None
            ),
            "pain_severity": pain,
            "recent_training_count": recent_training_count,
            "reasons": reasons,
            "evidence_snapshot": {"known_signal_count": len(reasons)},
            "rule_version": RecoveryRuleEngine.VERSION,
        }
        if snapshot is None:
            snapshot = RecoverySnapshot(user_id=user_id, snapshot_date=reference, **values)
            self.session.add(snapshot)
        else:
            for field, value in values.items():
                setattr(snapshot, field, value)
        await self.session.commit()
        message_by_status = {
            "good": "恢复信号良好，可按计划训练并保留 2–3 次余力。",
            "normal": "恢复状态普通，可按计划训练并根据热身感受调整。",
            "reduced": "恢复信号偏低，建议降低负荷或减少一组，避免力竭。",
            "insufficient_data": "数据不足，采用保守计划；不把缺失数据当作 0。",
        }
        return RecoveryRead(
            date=reference,
            status=status,
            reasons=reasons,
            sleep_duration_min=sleep.duration_min if sleep else None,
            resting_heart_rate=rhr,
            message=message_by_status[status],
        )
