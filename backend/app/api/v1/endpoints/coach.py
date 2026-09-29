from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.diet_coach import CoachChatRequest, CoachChatResponse
from app.services.diet_coach_orchestrator import DietCoachOrchestrator

router = APIRouter()


@router.post("/chat", response_model=DataResponse[CoachChatResponse])
async def chat(
    payload: CoachChatRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[CoachChatResponse]:
    return DataResponse(data=await DietCoachOrchestrator(session).chat(user.id, payload))
