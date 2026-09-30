from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.training import TrainingChatRequest, TrainingChatResponse
from app.services.training_coach_orchestrator import TrainingCoachOrchestrator

router = APIRouter()


@router.post("/chat", response_model=DataResponse[TrainingChatResponse])
async def training_chat(
    payload: TrainingChatRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TrainingChatResponse]:
    return DataResponse(data=await TrainingCoachOrchestrator(session).chat(user.id, payload))
