from dataclasses import dataclass, field
from typing import Literal


@dataclass(frozen=True, slots=True)
class HealthSafetyDecision:
    blocked: bool
    risk_level: Literal["normal", "caution", "urgent"]
    medical_boundary: bool = False
    message: str | None = None
    action: dict[str, object] = field(default_factory=dict)


class HealthSafetyService:
    @staticmethod
    def evaluate(intent: str, message: str) -> HealthSafetyDecision:
        value = message.lower()
        emergency = (
            "胸痛",
            "胸口疼",
            "严重呼吸困难",
            "喘不过气",
            "意识障碍",
            "昏迷",
            "严重低血糖",
            "高热伴意识",
            "大量出血",
            "严重过敏",
            "口角歪",
            "半边无力",
            "说话不清",
        )
        if intent == "urgent_symptom" or any(term in value for term in emergency):
            return HealthSafetyDecision(
                blocked=True,
                risk_level="urgent",
                medical_boundary=True,
                message=(
                    "这些描述可能涉及需要立即处理的情况。请停止运动，立即联系当地急救服务"
                    "（中国大陆 120）或尽快前往急诊，并让身边的人陪同。不要等待 AI 进一步判断。"
                ),
                action={"type": "seek_urgent_care", "label": "立即寻求紧急医疗帮助"},
            )
        if intent == "medication_question":
            return HealthSafetyDecision(
                blocked=False,
                risk_level="caution",
                medical_boundary=True,
                message="我不能建议停用、增减或替换处方药；这需要联系开药医生。",
                action={"type": "contact_clinician", "label": "联系开药医生"},
            )
        if intent == "medical_diagnosis_request":
            return HealthSafetyDecision(
                blocked=False,
                risk_level="caution",
                medical_boundary=True,
                message="我不能根据单个指标、照片或文字确认诊断。",
                action={"type": "contact_clinician", "label": "咨询医生"},
            )
        if any(term in value for term in ("完全不吃", "饿一天", "催吐", "断食补偿")):
            return HealthSafetyDecision(
                blocked=True,
                risk_level="caution",
                medical_boundary=False,
                message=(
                    "一次吃多不需要通过禁食、催吐或惩罚性运动补偿。下一餐恢复正常节奏，"
                    "补水并继续原计划即可。"
                ),
                action={"type": "none", "label": "恢复正常饮食"},
            )
        return HealthSafetyDecision(blocked=False, risk_level="normal")
