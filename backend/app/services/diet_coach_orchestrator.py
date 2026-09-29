import hashlib
import json
from datetime import UTC, datetime, timedelta
from time import perf_counter
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.prompts import DIET_COACH_PROMPT_VERSION
from app.core.config import get_settings
from app.core.errors import AppError
from app.models.diet_coach import CoachConversation, CoachMessage
from app.models.meal_analysis import AIUsageLog
from app.providers.ai import build_coach_provider
from app.providers.ai.base import CoachProvider
from app.repositories.diet_coach_repository import DietCoachRepository
from app.schemas.diet_coach import (
    CoachChatRequest,
    CoachChatResponse,
    CoachGeneratedReply,
    CoachSuggestedAction,
)
from app.services.coach_context_builder import CoachContextBuilder
from app.services.coach_safety_service import CoachSafetyService
from app.services.intent_classifier import IntentClassifier
from app.services.knowledge_retrieval import KnowledgeRetriever, NoopKnowledgeRetriever


class DietCoachOrchestrator:
    def __init__(
        self,
        session: AsyncSession,
        provider: CoachProvider | None = None,
        retriever: KnowledgeRetriever | None = None,
    ) -> None:
        self.session = session
        self.repo = DietCoachRepository(session)
        self.provider = provider or build_coach_provider()
        self.retriever = retriever or NoopKnowledgeRetriever()

    async def chat(self, user_id: UUID, payload: CoachChatRequest) -> CoachChatResponse:
        intent = IntentClassifier.classify(payload.message)
        conversation = await self._conversation(user_id, payload.conversation_id, payload.message)
        safety = CoachSafetyService.evaluate(intent, payload.message)
        used_context: list[str] = []
        safety_flags: list[str] = []
        context: dict[str, object] = {}
        references: list[dict[str, str]] = []
        if safety.blocked:
            generated = CoachGeneratedReply(
                message=safety.message or "当前请求需要专业人员处理。",
                suggested_actions=[
                    CoachSuggestedAction(type="none", label="无需应用内操作", target_id=None)
                ],
                safety_notice=safety.notice,
                risk_level="urgent" if intent == "emergency_health" else "caution",
            )
            provider_name, model = "safety_layer", "deterministic-v1"
            safety_flags = [intent]
        else:
            context = await CoachContextBuilder(self.session).build(user_id, intent)
            references = await self.retriever.retrieve(payload.message, context)
            if references:
                context["knowledge_references"] = references
            used_context = sorted(context.keys())
            await self._check_daily_limit(user_id)
            started = perf_counter()
            response = await self.provider.respond(payload.message, intent, context)
            latency_ms = int((perf_counter() - started) * 1000)
            generated = CoachGeneratedReply.model_validate(response.payload)
            provider_name, model = response.provider, response.model
            self.session.add(
                AIUsageLog(
                    user_id=user_id,
                    provider=provider_name,
                    model=model,
                    task="diet_coach",
                    input_tokens=response.input_tokens,
                    output_tokens=response.output_tokens,
                    image_count=0,
                    latency_ms=latency_ms,
                    status="success",
                )
            )
        audit_snapshot: dict[str, object] = {
            "message": payload.message,
            "intent": intent,
            "context": context,
            "safety_flags": safety_flags,
        }
        input_snapshot_hash = hashlib.sha256(
            json.dumps(audit_snapshot, ensure_ascii=False, sort_keys=True, default=str).encode()
        ).hexdigest()
        stored_payload = generated.model_dump(mode="json")
        stored_payload["input_snapshot_hash"] = input_snapshot_hash
        stored_payload["rule_version"] = "diet_rules_v1"
        stored_payload["prompt_version"] = DIET_COACH_PROMPT_VERSION
        stored_payload["model"] = model
        self.session.add(
            CoachMessage(
                conversation_id=conversation.id,
                role="user",
                content=payload.message,
                intent=intent,
            )
        )
        self.session.add(
            CoachMessage(
                conversation_id=conversation.id,
                role="assistant",
                content=generated.message,
                intent=intent,
                provider=provider_name,
                model=model,
                prompt_version=DIET_COACH_PROMPT_VERSION,
                structured_payload=stored_payload,
            )
        )
        await self.session.commit()
        return CoachChatResponse(
            conversation_id=conversation.id,
            intent=intent,
            message=generated.message,
            suggested_actions=generated.suggested_actions,
            safety_notice=generated.safety_notice,
            provider=provider_name,
            model=model,
            context_version="coach_context_v1",
            used_context=used_context,
            safety_flags=safety_flags,
            references=[item.get("url", "") for item in references] if not safety.blocked else [],
        )

    async def _check_daily_limit(self, user_id: UUID) -> None:
        since = datetime.now(UTC) - timedelta(hours=24)
        count = await self.session.scalar(
            select(func.count(AIUsageLog.id)).where(
                AIUsageLog.user_id == user_id,
                AIUsageLog.task == "diet_coach",
                AIUsageLog.created_at >= since,
            )
        )
        if int(count or 0) >= get_settings().coach_daily_limit:
            raise AppError("coach_daily_limit", "Daily AI coach limit reached.", 429)

    async def _conversation(
        self, user_id: UUID, conversation_id: UUID | None, message: str
    ) -> CoachConversation:
        if conversation_id:
            existing = await self.repo.conversation(user_id, conversation_id)
            if existing is None:
                raise AppError("conversation_not_found", "Coach conversation was not found.", 404)
            return existing
        conversation = CoachConversation(user_id=user_id, title=message[:80])
        self.session.add(conversation)
        await self.session.flush()
        return conversation
