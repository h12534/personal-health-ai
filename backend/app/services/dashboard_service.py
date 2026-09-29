from datetime import date, timedelta
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.weight_repository import WeightRepository
from app.schemas.dashboard import DashboardToday
from app.services.weight_service import build_weight_trend


class DashboardService:
    def __init__(self, session: AsyncSession) -> None:
        self.weight_repository = WeightRepository(session)

    async def today(self, user_id: UUID, today: date | None = None) -> DashboardToday:
        reference = today or date.today()
        logs = await self.weight_repository.list_for_user(
            user_id, date_from=reference - timedelta(days=27), date_to=reference
        )
        trend = build_weight_trend(logs, today=reference)
        today_log = next((item for item in logs if item.measured_on == reference), None)
        action = self._next_action(today_log is not None, trend.week_change_kg)
        return DashboardToday(
            date=reference,
            today_weight_kg=float(today_log.weight_kg) if today_log else None,
            average_7d_kg=trend.average_7d_kg,
            week_change_kg=trend.week_change_kg,
            morning_weight_completed=today_log is not None,
            ai_next_action=action,
        )

    @staticmethod
    def _next_action(has_weight: bool, week_change: float | None) -> str:
        if not has_weight:
            return "今天还没有记录晨重。起床如厕后、进食饮水前称重即可；单日波动不决定策略。"
        if week_change is None:
            return "已完成今日称重。继续积累记录，至少 7–14 天后再判断真实趋势。"
        if week_change < -1.0:
            return "近期下降较快。先保证正常饮食、蛋白质和恢复，不要因单周数据继续削减热量。"
        return "已完成今日称重。保持现实可执行的饮食和步行计划，按连续趋势而非单日体重调整。"
