from dataclasses import dataclass
from typing import Literal


@dataclass(frozen=True, slots=True)
class TrainingSafetyDecision:
    blocked: bool
    risk_level: Literal["normal", "caution", "urgent"] = "normal"
    message: str | None = None
    notice: str | None = None


class TrainingSafetyService:
    EMERGENCY = (
        "胸痛",
        "晕厥",
        "晕倒",
        "无法呼吸",
        "严重呼吸困难",
        "无法负重",
        "明显肿胀",
        "剧烈疼痛",
        "chest pain",
        "faint",
    )
    PUNITIVE = (
        "吃多了",
        "吃撑",
        "暴食",
        "跑两个小时",
        "跑2小时",
        "补回来",
        "惩罚",
        "抵消热量",
        "compensate",
    )

    @classmethod
    def evaluate(cls, message: str) -> TrainingSafetyDecision:
        normalized = message.lower()
        if any(value in normalized for value in cls.EMERGENCY):
            return TrainingSafetyDecision(
                blocked=True,
                risk_level="urgent",
                message=(
                    "请立即停止训练。这些表现可能需要紧急医疗评估；如有胸痛、晕厥、"
                    "严重呼吸困难或无法负重，请联系当地急救服务（中国大陆 120）并请身边人陪同。"
                ),
                notice="AI 训练教练不能处理急症，也不会建议继续训练。",
            )
        if any(value in normalized for value in cls.PUNITIVE):
            return TrainingSafetyDecision(
                blocked=True,
                risk_level="caution",
                message=(
                    "我不会用长时间跑步或双倍训练来惩罚一次吃多。今天恢复正常饮食与活动节奏，"
                    "可以轻松步行，但不要把手表热量按 1:1 吃回或强行抵消。"
                ),
                notice="若补偿性运动冲动反复出现，请寻求医生或心理/营养专业人员支持。",
            )
        return TrainingSafetyDecision(blocked=False)
