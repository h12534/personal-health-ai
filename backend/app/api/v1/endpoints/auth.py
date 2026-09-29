from fastapi import APIRouter, Depends, Request, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import (
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
    UserRead,
)
from app.schemas.common import DataResponse
from app.services.auth_service import AuthService

router = APIRouter()


def _user_agent(request: Request) -> str | None:
    return request.headers.get("user-agent")


@router.post(
    "/register", response_model=DataResponse[TokenPair], status_code=status.HTTP_201_CREATED
)
async def register(
    payload: RegisterRequest,
    request: Request,
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TokenPair]:
    tokens = await AuthService(session).register(
        str(payload.email), payload.password, _user_agent(request)
    )
    return DataResponse(data=tokens)


@router.post("/login", response_model=DataResponse[TokenPair])
async def login(
    payload: LoginRequest,
    request: Request,
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TokenPair]:
    tokens = await AuthService(session).login(
        str(payload.email), payload.password, _user_agent(request)
    )
    return DataResponse(data=tokens)


@router.post("/refresh", response_model=DataResponse[TokenPair])
async def refresh(
    payload: RefreshRequest,
    request: Request,
    session: AsyncSession = Depends(get_db),
) -> DataResponse[TokenPair]:
    tokens = await AuthService(session).refresh(payload.refresh_token, _user_agent(request))
    return DataResponse(data=tokens)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    payload: LogoutRequest,
    session: AsyncSession = Depends(get_db),
) -> Response:
    await AuthService(session).logout(payload.refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=DataResponse[UserRead])
async def me(user: User = Depends(get_current_user)) -> DataResponse[UserRead]:
    return DataResponse(data=UserRead.model_validate(user))
