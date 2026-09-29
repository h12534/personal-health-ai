from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import DataResponse
from app.schemas.dashboard import DashboardToday
from app.services.dashboard_service import DashboardService

router = APIRouter()


@router.get("/today", response_model=DataResponse[DashboardToday])
async def today(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
) -> DataResponse[DashboardToday]:
    dashboard = await DashboardService(session).today(user.id)
    return DataResponse(data=dashboard)
