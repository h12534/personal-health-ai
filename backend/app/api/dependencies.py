from uuid import UUID

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.security import decode_token
from app.db.session import get_db
from app.models.user import User
from app.providers.ai import build_vision_provider
from app.providers.ai.base import VisionProvider
from app.providers.storage import get_storage_provider
from app.providers.storage.base import StorageProvider
from app.repositories.user_repository import UserRepository

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    session: AsyncSession = Depends(get_db),
) -> User:
    if credentials is None:
        raise AppError("not_authenticated", "Authentication is required.", 401)
    try:
        payload = decode_token(credentials.credentials, "access")
        user_id = UUID(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError) as exc:
        raise AppError("invalid_access_token", "Access token is invalid or expired.", 401) from exc
    user = await UserRepository(session).by_id(user_id)
    if user is None or not user.is_active:
        raise AppError("inactive_user", "User is inactive or unavailable.", 401)
    return user


CurrentUser = User


def get_vision_provider() -> VisionProvider:
    return build_vision_provider()


def get_private_storage() -> StorageProvider:
    return get_storage_provider()
