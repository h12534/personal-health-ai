from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_user,
    get_embedding_provider,
    get_health_answer_provider,
)
from app.db.session import get_db
from app.models.user import User
from app.providers.ai.base import EmbeddingProvider, HealthAnswerProvider
from app.schemas.common import DataResponse
from app.schemas.health_knowledge import HealthChatRequest, HealthChatResponse
from app.services.health_ai_orchestrator import HealthAIOrchestrator

router = APIRouter()


@router.post("/chat", response_model=DataResponse[HealthChatResponse])
async def health_chat(
    payload: HealthChatRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    embedding: EmbeddingProvider = Depends(get_embedding_provider),
    provider: HealthAnswerProvider = Depends(get_health_answer_provider),
) -> DataResponse[HealthChatResponse]:
    value = await HealthAIOrchestrator(session, embedding, provider).chat(user.id, payload)
    return DataResponse(data=value)
