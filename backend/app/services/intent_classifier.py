import re

INTENTS = {
    "meal_decision",
    "meal_recommendation",
    "daily_summary",
    "nutrition_question",
    "weight_progress",
    "diet_plan",
    "overeating_recovery",
    "hunger",
    "restaurant_choice",
    "canteen_choice",
    "food_comparison",
    "general_chat",
    "unsupported_medical",
    "emergency_health",
}


class IntentClassifier:
    RULES: list[tuple[str, tuple[str, ...]]] = [
        (
            "emergency_health",
            (
                "胸痛",
                "呼吸困难",
                "意识异常",
                "严重低血糖",
                "抽搐",
                "昏迷",
                "晕倒",
                "自杀",
                "急救",
                "severe chest pain",
            ),
        ),
        (
            "unsupported_medical",
            ("诊断", "药量", "停药", "处方", "胰岛素剂量", "减肥药", "eating disorder"),
        ),
        ("overeating_recovery", ("暴食", "吃撑", "吃多了", "催吐", "补偿", "饿一天")),
        ("hunger", ("饿", "饥饿", "想吃东西", "馋")),
        ("canteen_choice", ("食堂", "档口", "canteen")),
        (
            "restaurant_choice",
            ("餐厅", "外卖", "便利店", "便利商店", "restaurant", "takeout", "convenience store"),
        ),
        ("food_comparison", ("哪个好", "对比", "比较", "还是")),
        ("weight_progress", ("体重", "平台期", "减了", "趋势", "胖了")),
        ("daily_summary", ("今天吃", "今日总结", "今天还差", "今天营养")),
        ("diet_plan", ("饮食计划", "目标热量", "减脂计划", "增肌计划")),
        ("meal_recommendation", ("推荐", "吃什么", "怎么搭配")),
        ("meal_decision", ("能不能吃", "该不该吃", "下一餐", "晚饭", "午饭", "早餐")),
        ("nutrition_question", ("热量", "蛋白质", "碳水", "脂肪", "营养")),
    ]

    @classmethod
    def classify(cls, message: str) -> str:
        normalized = re.sub(r"\s+", " ", message.lower()).strip()
        for intent, keywords in cls.RULES:
            if any(keyword in normalized for keyword in keywords):
                return intent
        return "general_chat"
