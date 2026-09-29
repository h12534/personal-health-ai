from dataclasses import dataclass


@dataclass(frozen=True)
class SafetyDecision:
    blocked: bool
    message: str | None = None
    notice: str | None = None


class CoachSafetyService:
    @staticmethod
    def evaluate(intent: str, message: str) -> SafetyDecision:
        if intent == "emergency_health":
            return SafetyDecision(
                blocked=True,
                message=(
                    "这可能需要紧急医疗帮助。请立即联系当地急救服务（中国大陆 120），"
                    "并让身边的人陪同；不要等待饮食建议。"
                ),
                notice="AI 饮食教练不能处理急症。",
            )
        if intent == "unsupported_medical":
            return SafetyDecision(
                blocked=True,
                message="我不能诊断疾病或建议改变药物剂量。请把症状、用药和饮食记录交给医生或注册营养专业人员评估。",
                notice="本回答不构成医疗诊断或用药建议。",
            )
        risky = (
            "催吐",
            "饿一天",
            "断食补偿",
            "不吃饭",
            "极低热量",
            "脱水",
            "过度运动",
            "惩罚性运动",
            "跑步补偿",
        )
        if intent == "overeating_recovery" or any(value in message for value in risky):
            return SafetyDecision(
                blocked=True,
                message="一顿吃多了不需要惩罚或补偿。下一餐照常吃一份含蛋白质、蔬菜和适量主食的正常餐，补水并回到原计划；不要催吐、断食或追加惩罚性运动。",
                notice="若暴食或补偿冲动反复出现并影响生活，请尽快寻求医生或心理/营养专业人员支持。",
            )
        return SafetyDecision(blocked=False)
