from decimal import Decimal
from typing import Literal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.providers.ai import build_coach_provider
from app.providers.ai.base import CoachProvider
from app.schemas.training import (
    TrainingChatRequest,
    TrainingChatResponse,
    TrainingSuggestedAction,
)
from app.services.progression_service import ProgressionService
from app.services.training_context_builder import TrainingContextBuilder
from app.services.training_intent_classifier import TrainingIntentClassifier
from app.services.training_safety_service import TrainingSafetyService


class TrainingCoachOrchestrator:
    def __init__(self, session: AsyncSession, provider: CoachProvider | None = None) -> None:
        self.session = session
        self.provider = provider or build_coach_provider()

    async def chat(self, user_id: UUID, payload: TrainingChatRequest) -> TrainingChatResponse:
        intent = TrainingIntentClassifier.classify(payload.message)
        safety = TrainingSafetyService.evaluate(payload.message)
        if safety.blocked:
            return TrainingChatResponse(
                intent=intent,
                message=safety.message or "请停止训练并寻求专业帮助。",
                suggested_actions=[TrainingSuggestedAction(type="none", label="停止当前训练")],
                safety_notice=safety.notice,
                risk_level=safety.risk_level,
                provider="safety_layer",
                model="deterministic-v1",
                used_context=[],
            )
        context = await TrainingContextBuilder(self.session).build(user_id, intent, payload.message)
        provider_response = await self.provider.respond(payload.message, intent, context)
        message, actions, risk_level, notice = self._program_response(intent, context)
        if message is None:
            message = str(
                provider_response.payload.get(
                    "message", "我会结合训练计划、最近表现和恢复状态给出保守建议。"
                )
            )
        return TrainingChatResponse(
            intent=intent,
            message=message,
            suggested_actions=actions,
            safety_notice=notice,
            risk_level=risk_level,
            provider=provider_response.provider,
            model=provider_response.model,
            used_context=sorted(context.keys()),
        )

    @staticmethod
    def _program_response(
        intent: str, context: dict[str, object]
    ) -> tuple[
        str | None,
        list[TrainingSuggestedAction],
        Literal["normal", "caution", "urgent"],
        str | None,
    ]:
        if intent == "weight_selection":
            exercise = context.get("exercise")
            recent = context.get("recent_sets")
            recovery = context.get("recovery") or {}
            if isinstance(exercise, dict) and isinstance(recent, list) and recent:
                latest_date = recent[0]["date"]
                latest = [item for item in recent if item["date"] == latest_date]
                weight = Decimal(str(latest[0]["weight_kg"]))
                reps = [int(item["reps"]) for item in latest]
                rirs = [
                    Decimal(str(item["rir"])) if item.get("rir") is not None else None
                    for item in latest
                ]
                recovery_status = (
                    str(recovery.get("status", "normal"))
                    if isinstance(recovery, dict)
                    else "normal"
                )
                suggestion = ProgressionService.suggest(
                    weight_kg=weight,
                    reps=reps,
                    rir=rirs,
                    target_sets=3,
                    target_rep_min=8,
                    target_rep_max=12,
                    movement_pattern=str(exercise["movement_pattern"]),
                    recovery_status=recovery_status,
                )
                return (
                    f"{exercise['name']}下次建议 {suggestion.suggested_weight_kg} kg。"
                    f"{suggestion.reason} 这是待确认建议，不会直接修改你的计划。",
                    [
                        TrainingSuggestedAction(
                            type="apply_progression",
                            label="查看并应用建议",
                            target_id=str(exercise["id"]),
                            payload=suggestion.model_dump(mode="json"),
                        )
                    ],
                    "normal",
                    None,
                )
            return (
                "最近记录不足。先选一个能在目标次数内保留 2–3 次余力的重量，"
                "完成后再用双进阶规则调整。",
                [TrainingSuggestedAction(type="none", label="先记录一组")],
                "normal",
                None,
            )
        if intent in {"missed_workout", "schedule_change"}:
            return (
                "错过一天不需要补双倍训练。按顺序把本次训练顺延，"
                "并尽量在两次力量训练之间保留约 48 小时。",
                [
                    TrainingSuggestedAction(
                        type="reschedule_plan",
                        label="查看顺延方案",
                        payload={"double_session": False, "minimum_recovery_hours": 48},
                    )
                ],
                "normal",
                None,
            )
        if intent in {"recovery", "sleep_recovery"}:
            recovery = context.get("recovery") or {}
            if isinstance(recovery, dict):
                return (
                    str(recovery.get("message", "按热身感受保守调整训练。")),
                    [TrainingSuggestedAction(type="open_recovery", label="查看恢复依据")],
                    "caution" if recovery.get("status") == "reduced" else "normal",
                    "单晚睡眠阶段不用于诊断或大幅调整计划。",
                )
        if intent == "today_workout":
            plan = context.get("active_plan")
            status = context.get("today_training_status")
            if isinstance(plan, dict):
                return (
                    f"当前计划是“{plan['name']}”，今天状态为 {status}。"
                    "先完成计划中的下一训练日，工作组保留 2–3 次余力。",
                    [TrainingSuggestedAction(type="start_workout", label="开始今日训练")],
                    "normal",
                    None,
                )
        if intent == "cardio":
            return (
                "当前阶段优先快走、坡度走、椭圆机或自行车，"
                "以可持续强度逐步增加；不默认安排大量跑步或 HIIT。",
                [TrainingSuggestedAction(type="none", label="保持低冲击")],
                "normal",
                None,
            )
        return None, [TrainingSuggestedAction(type="none", label="无需应用操作")], "normal", None
