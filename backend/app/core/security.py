import hashlib
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import jwt
from pwdlib import PasswordHash

from app.core.config import get_settings

password_hash = PasswordHash.recommended()


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, encoded_hash: str) -> bool:
    return password_hash.verify(password, encoded_hash)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_token(
    subject: uuid.UUID,
    token_type: Literal["access", "refresh"],
    expires_delta: timedelta,
) -> tuple[str, datetime]:
    settings = get_settings()
    now = datetime.now(UTC)
    expires_at = now + expires_delta
    payload: dict[str, Any] = {
        "sub": str(subject),
        "type": token_type,
        "jti": str(uuid.uuid4()),
        "iat": now,
        "exp": expires_at,
    }
    token = jwt.encode(payload, settings.app_secret_key, algorithm="HS256")
    return token, expires_at


def decode_token(token: str, expected_type: Literal["access", "refresh"]) -> dict[str, Any]:
    settings = get_settings()
    payload: dict[str, Any] = jwt.decode(token, settings.app_secret_key, algorithms=["HS256"])
    if payload.get("type") != expected_type:
        raise jwt.InvalidTokenError("Unexpected token type")
    return payload
