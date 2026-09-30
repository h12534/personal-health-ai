import re


class TrainingIntentClassifier:
    RULES: list[tuple[str, tuple[str, ...]]] = [
        (
            "pain_or_discomfort",
            ("疼", "疼痛", "肿", "扭伤", "拉伤", "膝盖", "肩痛", "腰痛", "pain", "injury"),
        ),
        ("missed_workout", ("没练", "错过训练", "没去健身", "missed workout", "skip")),
        ("schedule_change", ("改到", "换一天", "调整训练日", "改计划", "reschedule")),
        ("weight_selection", ("用多少重量", "多少公斤", "加重量", "减重量", "weight")),
        ("progression", ("进阶", "渐进", "下次怎么加", "progression")),
        ("today_workout", ("今天练什么", "今日训练", "今天训练", "workout today")),
        ("exercise_help", ("怎么做", "动作要领", "姿势", "技术", "form")),
        ("training_progress", ("训练进步", "训练趋势", "pr", "一rm", "1rm", "容量")),
        ("sleep_recovery", ("睡眠", "睡了", "静息心率", "sleep")),
        ("recovery", ("恢复", "疲劳", "累", "酸痛", "rest day")),
        ("cardio", ("有氧", "跑步", "椭圆机", "自行车", "坡度走", "cardio")),
        ("steps", ("步数", "走路", "散步", "steps")),
    ]

    @classmethod
    def classify(cls, message: str) -> str:
        normalized = re.sub(r"\s+", " ", message.lower()).strip()
        for intent, keywords in cls.RULES:
            if any(keyword in normalized for keyword in keywords):
                return intent
        return "general_training"
