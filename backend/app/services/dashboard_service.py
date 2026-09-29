from datetime import date, datetime, time, timedelta
from decimal import Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.nutrition_repository import NutritionGoalRepository
from app.repositories.weight_repository import WeightRepository
from app.schemas.dashboard import DashboardToday
from app.schemas.nutrition import DailyNutrition
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.weight_service import build_weight_trend


class DashboardService:
    def __init__(self, session: AsyncSession) -> None:
        self.weight_repository = WeightRepository(session)
        self.nutrition = DailyNutritionService(session)
        self.goals = NutritionGoalRepository(session)

    async def today(self, user_id: UUID, today: date | None = None) -> DashboardToday:
        daily = await self.nutrition.daily(user_id, today)
        reference = daily.date
        logs = await self.weight_repository.list_for_user(
            user_id, date_from=reference - timedelta(days=27), date_to=reference
        )
        trend = build_weight_trend(logs, today=reference)
        today_log = next((item for item in logs if item.measured_on == reference), None)
        goal = await self.goals.current(user_id, reference)
        timezone = await self.nutrition.timezone(user_id)
        now = datetime.now(timezone)
        action = DashboardRuleEngine.next_action(
            daily=daily,
            calorie_target=goal.calorie_target if goal else None,
            protein_target=goal.protein_target_g if goal else None,
            has_weight=today_log is not None,
            week_change=trend.week_change_kg,
            local_time=now.time(),
        )
        return DashboardToday(
            date=reference,
            today_weight_kg=float(today_log.weight_kg) if today_log else None,
            average_7d_kg=trend.average_7d_kg,
            week_change_kg=trend.week_change_kg,
            calories_consumed=int(daily.totals.calories.quantize(Decimal("1"))),
            calories_target=goal.calorie_target if goal else None,
            protein_g=float(daily.totals.protein),
            protein_target_g=float(goal.protein_target_g) if goal else None,
            carbs_g=float(daily.totals.carbs),
            carbs_target_g=float(goal.carbs_target_g) if goal and goal.carbs_target_g else None,
            fat_g=float(daily.totals.fat),
            fat_target_g=float(goal.fat_target_g) if goal and goal.fat_target_g else None,
            fiber_g=float(daily.totals.fiber),
            fiber_target_g=float(goal.fiber_target_g) if goal else None,
            morning_weight_completed=today_log is not None,
            breakfast_logged=daily.meal_counts.get("breakfast", 0) > 0,
            lunch_logged=daily.meal_counts.get("lunch", 0) > 0,
            dinner_logged=daily.meal_counts.get("dinner", 0) > 0,
            ai_next_action=action,
        )


class DashboardRuleEngine:
    """Deterministic Phase 2 guidance; no AI inference or external calls."""

    @staticmethod
    def next_action(
        *,
        daily: DailyNutrition,
        calorie_target: int | None,
        protein_target: Decimal | None,
        has_weight: bool,
        week_change: float | None,
        local_time: time,
    ) -> str:
        if not has_weight:
            return "今天还没有记录晨重。起床如厕后、进食饮水前称重即可；单日波动不决定策略。"
        if local_time >= time(13) and daily.meal_counts.get("lunch", 0) == 0:
            return "午餐尚未记录。先补记实际吃过的食物和份量，再根据全天剩余额度安排晚餐。"
        if calorie_target and daily.totals.calories >= Decimal(str(calorie_target)):
            return "今日热量已达到目标。晚些时候优先选择无糖饮品和低能量食物，不必用极端节食补偿。"
        if (
            protein_target
            and local_time >= time(17)
            and daily.totals.protein < protein_target * Decimal("0.6")
        ):
            return "今天的蛋白质进度偏慢。下一餐可优先安排鸡蛋、奶、豆制品或瘦肉等常见来源。"
        if week_change is None:
            return "已完成今日称重。继续积累记录，至少 7–14 天后再判断真实趋势。"
        if week_change < -1.0:
            return "近期下降较快。先保证正常饮食、蛋白质和恢复，不要因单周数据继续削减热量。"
        return "已完成今日称重。保持现实可执行的饮食和步行计划，按连续趋势而非单日体重调整。"
