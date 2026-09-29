from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal
from statistics import pstdev
from typing import Literal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.weight_log import WeightLog
from app.repositories.weight_repository import WeightRepository
from app.schemas.diet_coach import WeightTrendRead


def _q(value: float | Decimal) -> Decimal:
    return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


class WeightTrendCalculator:
    @staticmethod
    def calculate(
        logs: list[WeightLog],
        as_of: date,
        adherence_rate: Decimal = Decimal("0"),
    ) -> WeightTrendRead:
        by_day = {
            log.measured_on: Decimal(log.weight_kg) for log in logs if log.measured_on <= as_of
        }

        def average(start_days_ago: int, end_days_ago: int) -> Decimal | None:
            values = [
                value
                for day, value in by_day.items()
                if as_of - timedelta(days=start_days_ago)
                <= day
                <= as_of - timedelta(days=end_days_ago)
            ]
            return sum(values, Decimal("0")) / Decimal(len(values)) if values else None

        current = average(6, 0)
        previous = average(13, 7)
        observations_14d = sum(as_of - timedelta(days=13) <= day <= as_of for day in by_day)
        change_7d = current - previous if current is not None and previous is not None else None

        def window_change(days: int) -> Decimal | None:
            half = max(3, min(7, days // 2))
            end_avg = average(half - 1, 0)
            start_values = [
                value
                for day, value in by_day.items()
                if as_of - timedelta(days=days - 1) <= day <= as_of - timedelta(days=days - half)
            ]
            if end_avg is None or not start_values:
                return None
            return end_avg - sum(start_values, Decimal("0")) / Decimal(len(start_values))

        change_14 = window_change(14)
        change_28 = window_change(28)
        weekly = change_14 / 2 if change_14 is not None else change_7d
        percent = weekly / current * 100 if weekly is not None and current else None
        last_14_values = [
            float(value)
            for day, value in by_day.items()
            if as_of - timedelta(days=13) <= day <= as_of
        ]
        stability = Decimal(str(pstdev(last_14_values))) if len(last_14_values) >= 2 else None
        eligible = (
            observations_14d >= 10 and adherence_rate >= Decimal("0.80") and change_28 is not None
        )
        plateau = bool(eligible and abs(change_28 or Decimal("0")) < Decimal("0.35"))
        direction: Literal["down", "stable", "up", "insufficient_data"]
        if current is None or previous is None:
            direction = "insufficient_data"
        elif abs(change_7d or Decimal("0")) < Decimal("0.15"):
            direction = "stable"
        elif (change_7d or Decimal("0")) < 0:
            direction = "down"
        else:
            direction = "up"
        note = (
            "数据不足，不判断平台期。至少需要 14 天内 10 次晨重、较完整饮食记录和 28 天跨度。"
            if not eligible
            else "趋势满足平台期规则，可生成小幅调整建议。"
            if plateau
            else "趋势仍在变化，继续当前计划并观察。"
        )
        return WeightTrendRead(
            as_of=as_of,
            sample_days=len(by_day),
            observations_14d=observations_14d,
            average_7d_kg=_q(current) if current is not None else None,
            previous_average_7d_kg=_q(previous) if previous is not None else None,
            change_7d_kg=_q(change_7d) if change_7d is not None else None,
            change_14d_kg=_q(change_14) if change_14 is not None else None,
            change_28d_kg=_q(change_28) if change_28 is not None else None,
            weekly_rate_kg=_q(weekly) if weekly is not None else None,
            weekly_rate_percent=_q(percent) if percent is not None else None,
            stability_kg=_q(stability) if stability is not None else None,
            direction=direction,
            plateau=plateau,
            plateau_eligible=eligible,
            note=note,
        )


class WeightTrendService:
    def __init__(self, session: AsyncSession) -> None:
        self.weights = WeightRepository(session)

    async def build(
        self, user_id: UUID, as_of: date | None = None, adherence_rate: Decimal = Decimal("0")
    ) -> WeightTrendRead:
        reference = as_of or date.today()
        logs = await self.weights.list_for_user(
            user_id, date_from=reference - timedelta(days=41), date_to=reference
        )
        return WeightTrendCalculator.calculate(logs, reference, adherence_rate)
