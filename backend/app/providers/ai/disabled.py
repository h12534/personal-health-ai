from typing import Any

from app.core.errors import AppError
from app.providers.ai.base import AIRequest, AIResponse


class DisabledAIProvider:
    async def generate(self, request: AIRequest) -> AIResponse:
        raise AppError("ai_not_configured", "AI provider has not been configured.", 503)

    async def embed(self, texts: list[str]) -> list[list[float]]:
        raise AppError("ai_not_configured", "Embedding provider has not been configured.", 503)

    async def analyze_food(self, image_bytes: bytes, context: dict[str, Any]) -> dict[str, Any]:
        raise AppError("ai_not_configured", "Vision provider has not been configured.", 503)
