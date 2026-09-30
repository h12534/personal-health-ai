from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.health_knowledge import HealthAIConversation, HealthAIMessage
from app.models.meal_analysis import AIUsageLog
from app.providers.ai.base import EmbeddingProvider, HealthAnswerProvider
from app.schemas.health_knowledge import (
    HealthChatRequest,
    HealthChatResponse,
    HealthSuggestedAction,
)
from app.services.health_context_builder import HealthContextBuilder
from app.services.health_intent_classifier import HealthIntentClassifier
from app.services.health_safety_service import HealthSafetyService
from app.services.knowledge_retrieval import HybridKnowledgeRetriever


class HealthQueryRewriter:
    CATEGORY_MAP = {
        "lab_explanation": ["blood_glucose", "blood_lipids", "metabolic_health"],
        "weight_health": ["body_weight_management", "fat_loss", "obesity"],
        "metabolic_health": ["metabolic_health", "insulin_resistance", "obesity"],
        "sleep_health": ["sleep", "recovery"],
        "nutrition_health": ["nutrition", "protein", "micronutrients"],
        "exercise_health": ["strength_training", "cardio", "injury_prevention"],
        "symptom_question": ["health_screening", "metabolic_health"],
        "medical_diagnosis_request": [
            "health_screening",
            "blood_glucose",
            "insulin_resistance",
            "metabolic_health",
        ],
        "medication_question": ["general_health"],
    }

    @classmethod
    def rewrite(cls, message: str, intent: str) -> tuple[str, list[str]]:
        expansions: list[str] = []
        lower = message.lower()
        if "hba1c" in lower or "糖化血红蛋白" in message:
            expansions.extend(["glycated hemoglobin", "blood glucose", "prediabetes"])
        if "黑棘皮" in message or "脖子发黑" in message:
            expansions.extend(["acanthosis nigricans", "insulin resistance", "obesity"])
        query = " ".join([message, *expansions]).strip()
        return query, cls.CATEGORY_MAP.get(intent, [])


class HealthAIOrchestrator:
    def __init__(
        self,
        session: AsyncSession,
        embedding: EmbeddingProvider,
        provider: HealthAnswerProvider,
    ) -> None:
        self.session = session
        self.embedding = embedding
        self.provider = provider

    async def chat(self, user_id: UUID, payload: HealthChatRequest) -> HealthChatResponse:
        intent = HealthIntentClassifier.classify(payload.message)
        safety = HealthSafetyService.evaluate(intent, payload.message)
        conversation = await self._conversation(user_id, payload.conversation_id, payload.message)
        self.session.add(
            HealthAIMessage(
                conversation_id=conversation.id,
                role="user",
                content=payload.message,
                structured_payload={"intent": intent},
                provider="user",
                model="none",
            )
        )
        if safety.blocked:
            response = HealthChatResponse(
                conversation_id=conversation.id,
                intent=intent,
                answer=safety.message or "请立即寻求专业帮助。",
                evidence=[],
                personal_context_used=[],
                risk_level=safety.risk_level,
                medical_boundary=safety.medical_boundary,
                suggested_actions=[HealthSuggestedAction.model_validate(safety.action)],
                provider="safety_layer",
                model="deterministic-v1",
                retrieval_method="safety_short_circuit",
            )
            await self._save_response(conversation.id, response)
            return response
        context = await HealthContextBuilder(self.session).build(user_id, intent, payload.message)
        rewritten, categories = HealthQueryRewriter.rewrite(payload.message, intent)
        retriever = HybridKnowledgeRetriever(self.session, self.embedding)
        evidence = await retriever.search(rewritten, categories)
        evidence_payload = [value.model_dump(mode="json") for value in evidence]
        generated = await self.provider.answer(payload.message, intent, context, evidence_payload)
        answer = generated.answer
        if safety.message:
            answer = f"{safety.message}\n\n{answer}"
        if not evidence:
            answer = (
                "当前知识库没有达到最低证据阈值的可靠来源，因此我不能把下面内容表述为确定医学结论。\n\n"
                + answer
            )
        actions = [
            HealthSuggestedAction.model_validate(safety.action)
            if safety.action
            else HealthSuggestedAction(type="none", label="无需操作")
        ]
        if context.get("lab_results"):
            first = context["lab_results"][0]
            if isinstance(first, dict):
                actions.append(
                    HealthSuggestedAction(
                        type="open_lab",
                        label="查看对应体检报告",
                        target_id=str(first.get("report_id")),
                    )
                )
        response = HealthChatResponse(
            conversation_id=conversation.id,
            intent=intent,
            answer=answer,
            evidence=evidence,
            personal_context_used=sorted(
                key for key in context if key not in {"context_version", "as_of"}
            ),
            risk_level=safety.risk_level,
            medical_boundary=safety.medical_boundary,
            suggested_actions=actions,
            provider=generated.provider,
            model=generated.model,
            retrieval_method=retriever.METHOD,
        )
        await self._save_response(conversation.id, response)
        self.session.add(
            AIUsageLog(
                user_id=user_id,
                provider=generated.provider,
                model=generated.model,
                task="health_chat",
                input_tokens=generated.input_tokens,
                output_tokens=generated.output_tokens,
                image_count=0,
                latency_ms=0,
                status="success",
            )
        )
        self.session.add_all(
            [
                AIUsageLog(
                    user_id=user_id,
                    provider=self.embedding.name,
                    model=self.embedding.model,
                    task="rag_retrieval",
                    input_tokens=len(rewritten),
                    output_tokens=len(evidence) * self.embedding.dimension,
                    image_count=0,
                    latency_ms=0,
                    status="success",
                ),
                AIUsageLog(
                    user_id=user_id,
                    provider="deterministic",
                    model="rerank_v1",
                    task="rerank",
                    input_tokens=len(evidence),
                    output_tokens=len(evidence),
                    image_count=0,
                    latency_ms=0,
                    status="success",
                ),
            ]
        )
        await self.session.commit()
        return response

    async def _conversation(
        self, user_id: UUID, conversation_id: UUID | None, message: str
    ) -> HealthAIConversation:
        if conversation_id is not None:
            value = await self.session.scalar(
                select(HealthAIConversation).where(
                    HealthAIConversation.id == conversation_id,
                    HealthAIConversation.user_id == user_id,
                    HealthAIConversation.deleted_at.is_(None),
                )
            )
            if value is None:
                raise AppError("health_conversation_not_found", "Conversation was not found.", 404)
            return value
        value = HealthAIConversation(user_id=user_id, title=message[:80], active=True)
        self.session.add(value)
        await self.session.flush()
        return value

    async def _save_response(self, conversation_id: UUID, response: HealthChatResponse) -> None:
        self.session.add(
            HealthAIMessage(
                conversation_id=conversation_id,
                role="assistant",
                content=response.answer,
                structured_payload=response.model_dump(mode="json"),
                provider=response.provider,
                model=response.model,
            )
        )
        conversation = await self.session.get(HealthAIConversation, conversation_id)
        if conversation is not None:
            conversation.updated_at = datetime.now(UTC)
        await self.session.commit()
