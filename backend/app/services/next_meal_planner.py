from datetime import date, datetime
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.repositories.nutrition_repository import NutritionGoalRepository
from app.schemas.diet_coach import MealTargetRange, NextMealPlanRead
from app.services.daily_nutrition_service import DailyNutritionService


class NextMealPlanner:
    def __init__(self, session: AsyncSession) -> None:
        self.daily = DailyNutritionService(session)
        self.goals = NutritionGoalRepository(session)

    async def plan(
        self, user_id: UUID, on_date: date | None = None, hour: int | None = None
    ) -> NextMealPlanRead:
        reference = on_date or date.today()
        daily = await self.daily.daily(user_id, reference)
        goal = await self.goals.current(user_id, reference)
        if goal is None:
            raise AppError("nutrition_goal_not_found", "Set a nutrition goal first.", 404)
        current_hour = datetime.now().hour if hour is None else max(0, min(23, hour))
        if current_hour < 10 and daily.meal_counts.get("breakfast", 0) == 0:
            meal_type, share = "breakfast", Decimal("0.25")
        elif current_hour < 15 and daily.meal_counts.get("lunch", 0) == 0:
            meal_type, share = "lunch", Decimal("0.35")
        elif current_hour < 21 and daily.meal_counts.get("dinner", 0) == 0:
            meal_type, share = "dinner", Decimal("0.35")
        else:
            meal_type, share = "snack", Decimal("0.15")
        remaining_calories = int(Decimal(goal.calorie_target) - daily.totals.calories)
        remaining_protein = max(Decimal("0"), goal.protein_target_g - daily.totals.protein)
        over_target = remaining_calories <= 0
        base = Decimal(goal.calorie_target) * share
        if over_target:
            center = Decimal("350") if meal_type != "snack" else Decimal("200")
        else:
            center = min(max(Decimal("250"), base), Decimal(max(250, remaining_calories)))
        protein_center = max(
            Decimal("20"),
            min(
                Decimal("55"),
                remaining_protein * (Decimal("0.6") if meal_type != "snack" else Decimal("0.35")),
            ),
        )
        calorie_min = int((center * Decimal("0.8")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        calorie_max = int((center * Decimal("1.2")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        strategy = ["优先选择一份明确的蛋白质来源", "配足蔬菜，主食按当前饥饿程度调整"]
        if over_target:
            strategy.append("不跳餐、不惩罚性节食；正常吃一顿份量适中的餐，明天回到常规计划")
        if remaining_protein > Decimal("45"):
            strategy.append("今天蛋白质仍有较大缺口，可选瘦肉、鱼、蛋、豆制品或奶类")
        return NextMealPlanRead(
            meal_type=meal_type,
            target=MealTargetRange(
                calories_min=calorie_min,
                calories_max=calorie_max,
                protein_min_g=(protein_center * Decimal("0.8")).quantize(Decimal("1")),
                protein_max_g=(protein_center * Decimal("1.2")).quantize(Decimal("1")),
                carbs_hint_g=None,
                fat_hint_g=None,
            ),
            remaining_calories=remaining_calories,
            remaining_protein_g=remaining_protein.quantize(Decimal("0.1")),
            strategy=strategy,
            carb_guidance="主食正常吃；训练前后可把当天一部分碳水放在这餐，不改变全天总热量。",
            fat_guidance="若今天脂肪偏高，优先蒸煮炖或少额外酱汁，不需要完全无脂。",
            vegetable_guidance="至少加入一份蔬菜；食堂可选两份不同蔬菜。",
            notes=["范围是执行参考，不要求精确命中。", "蛋白粉只按普通食物记录，不是必需品。"],
            over_target=over_target,
            message="根据今天已记录的饮食，下一餐以可执行范围呈现，不要求精确命中单个数字。",
        )
