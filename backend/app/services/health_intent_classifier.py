class HealthIntentClassifier:
    @staticmethod
    def classify(message: str) -> str:
        value = message.lower()
        if any(
            term in value
            for term in (
                "胸痛",
                "胸口疼",
                "严重呼吸困难",
                "喘不过气",
                "意识障碍",
                "昏迷",
                "大量出血",
                "严重过敏",
                "口角歪",
                "半边无力",
            )
        ):
            return "urgent_symptom"
        if any(term in value for term in ("停药", "减药", "加药", "药量", "处方药")):
            return "medication_question"
        if any(
            term in value
            for term in (
                "是不是糖尿病",
                "是不是癌",
                "是不是黑棘皮",
                "确诊",
                "诊断",
                "得了什么病",
            )
        ):
            return "medical_diagnosis_request"
        if any(
            term in value
            for term in (
                "hba1c",
                "糖化血红蛋白",
                "血糖",
                "胆固醇",
                "尿酸",
                "转氨酶",
                "体检",
                "指标",
            )
        ):
            return "lab_explanation"
        if any(term in value for term in ("减脂速度", "体重", "胖了", "瘦了", "波动")):
            return "weight_health"
        if any(term in value for term in ("胰岛素", "代谢", "脂肪肝", "黑棘皮", "脖子发黑")):
            return "metabolic_health"
        if any(term in value for term in ("睡眠", "失眠", "睡不够")):
            return "sleep_health"
        if any(term in value for term in ("蛋白质", "饮食", "营养", "补剂", "肌酸", "咖啡因")):
            return "nutrition_health"
        if any(term in value for term in ("训练", "运动", "有氧", "力量")):
            return "exercise_health"
        if any(term in value for term in ("疼", "痛", "发黑", "症状", "不舒服")):
            return "symptom_question"
        return "general_health"
