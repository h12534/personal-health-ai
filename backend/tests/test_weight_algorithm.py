from datetime import date, timedelta
from decimal import Decimal
from uuid import uuid4

from app.models.weight_log import WeightLog
from app.services.weight_service import build_weight_trend


def test_moving_average_uses_calendar_window_and_ignores_single_day_policy() -> None:
    start = date(2026, 1, 1)
    logs = [
        WeightLog(
            user_id=uuid4(),
            measured_on=start + timedelta(days=index),
            weight_kg=Decimal(str(100 - index * 0.1)),
        )
        for index in range(14)
    ]
    result = build_weight_trend(logs, today=start + timedelta(days=13))
    assert result.average_7d_kg == 99.0
    assert result.previous_7d_average_kg == 99.7
    assert result.week_change_kg == -0.7
    assert result.points[-1].moving_average_7d == 99.0
