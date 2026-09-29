from typing import Any

from app.providers.ai.base import CoachProviderResponse


class MockCoachProvider:
    name = "mock"
    model = "mock-coach-v1"

    async def respond(
        self, message: str, intent: str, context: dict[str, Any]
    ) -> CoachProviderResponse:
        next_meal = context.get("next_meal") or {}
        if intent in {
            "meal_decision",
            "meal_recommendation",
            "canteen_choice",
            "restaurant_choice",
        }:
            target = next_meal.get("target") or {}
            reply = (
                f"下一餐可先按 {target.get('calories_min', 300)}–"
                f"{target.get('calories_max', 550)} kcal、"
                f"蛋白质至少 {target.get('protein_min_g', 25)} g 来选。优先一份蛋白质主菜，"
                "再配蔬菜和适量主食；不需要精确到每一克。"
            )
            actions = [{"type": "open_next_meal", "label": "查看下一餐方案", "target_id": None}]
        elif intent == "weight_progress":
            trend = context.get("weight_trend") or {}
            reply = f"先看多日趋势：{trend.get('note', '当前数据还不足以判断趋势。')}"
            actions = [{"type": "log_weight", "label": "记录晨重", "target_id": None}]
        elif intent == "daily_summary":
            daily = context.get("daily_nutrition") or {}
            totals = daily.get("totals") or {}
            reply = (
                f"今天目前记录约 {totals.get('calories', 0)} kcal、蛋白质 "
                f"{totals.get('protein', 0)} g。下一步按正常节奏安排下一餐即可。"
            )
            actions = [{"type": "open_next_meal", "label": "规划下一餐", "target_id": None}]
        elif intent == "hunger":
            reply = (
                "先确认这是生理饥饿还是疲劳、压力带来的进食冲动。若确实饿了，"
                "安排含蛋白质和纤维的正常加餐，不必硬扛。"
            )
            actions = [{"type": "log_hunger", "label": "记录饥饿感", "target_id": None}]
        else:
            reply = (
                "我会结合你的饮食记录、目标和多日趋势给建议。你可以问我下一餐怎么吃、"
                "今天还差多少，或这周是否需要调整。"
            )
            actions = [{"type": "none", "label": "无需操作", "target_id": None}]
        return CoachProviderResponse(
            payload={
                "message": reply,
                "suggested_actions": actions,
                "safety_notice": None,
                "risk_level": "normal",
            },
            provider=self.name,
            model=self.model,
        )
