from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import AppError
from app.core.security import (
    create_token,
    decode_token,
    hash_password,
    hash_refresh_token,
    verify_password,
)
from app.models.auth_session import AuthSession
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.auth import TokenPair


class AuthService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.users = UserRepository(session)
        self.settings = get_settings()

    async def register(self, email: str, password: str, user_agent: str | None) -> TokenPair:
        if await self.users.count() > 0:
            raise AppError(
                "registration_closed",
                "This private instance already has an owner.",
                status_code=409,
            )
        user = User(email=email.lower(), password_hash=hash_password(password), is_superuser=True)
        await self.users.add(user)
        tokens = await self._issue_pair(user.id, user_agent)
        await self.session.commit()
        return tokens

    async def login(self, email: str, password: str, user_agent: str | None) -> TokenPair:
        user = await self.users.by_email(email)
        if user is None or not verify_password(password, user.password_hash) or not user.is_active:
            raise AppError("invalid_credentials", "Invalid email or password.", status_code=401)
        tokens = await self._issue_pair(user.id, user_agent)
        await self.session.commit()
        return tokens

    async def refresh(self, raw_token: str, user_agent: str | None) -> TokenPair:
        try:
            payload = decode_token(raw_token, "refresh")
            user_id = UUID(payload["sub"])
        except (jwt.PyJWTError, KeyError, ValueError) as exc:
            raise AppError("invalid_refresh_token", "Refresh token is invalid.", 401) from exc

        token_hash = hash_refresh_token(raw_token)
        auth_session = await self.session.scalar(
            select(AuthSession).where(AuthSession.refresh_token_hash == token_hash)
        )
        now = datetime.now(UTC)
        if (
            auth_session is None
            or auth_session.user_id != user_id
            or auth_session.revoked_at is not None
            or self._as_utc(auth_session.expires_at) <= now
        ):
            raise AppError("invalid_refresh_token", "Refresh token is expired or revoked.", 401)

        auth_session.revoked_at = now
        tokens = await self._issue_pair(user_id, user_agent)
        await self.session.commit()
        return tokens

    async def logout(self, raw_token: str) -> None:
        token_hash = hash_refresh_token(raw_token)
        auth_session = await self.session.scalar(
            select(AuthSession).where(AuthSession.refresh_token_hash == token_hash)
        )
        if auth_session is not None and auth_session.revoked_at is None:
            auth_session.revoked_at = datetime.now(UTC)
            await self.session.commit()

    async def _issue_pair(self, user_id: UUID, user_agent: str | None) -> TokenPair:
        access_delta = timedelta(minutes=self.settings.access_token_expire_minutes)
        refresh_delta = timedelta(days=self.settings.refresh_token_expire_days)
        access_token, _ = create_token(user_id, "access", access_delta)
        refresh_token, refresh_expires = create_token(user_id, "refresh", refresh_delta)
        self.session.add(
            AuthSession(
                user_id=user_id,
                refresh_token_hash=hash_refresh_token(refresh_token),
                expires_at=refresh_expires,
                user_agent=(user_agent or "")[:512] or None,
            )
        )
        await self.session.flush()
        return TokenPair(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=int(access_delta.total_seconds()),
        )

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
