from typing import Any

from app.core.errors import AppError
from app.providers.ai.base import AIRequest, AIResponse, VisionProviderResponse


class DisabledAIProvider:
    name = "disabled"
    model = "disabled"
    is_remote = False

    async def generate(self, request: AIRequest) -> AIResponse:
        raise AppError("ai_not_configured", "AI provider has not been configured.", 503)

    async def embed(self, texts: list[str]) -> list[list[float]]:
        raise AppError("ai_not_configured", "Embedding provider has not been configured.", 503)

    async def analyze_meal(
        self, image_bytes: bytes, content_type: str, context: dict[str, Any]
    ) -> VisionProviderResponse:
        raise AppError("ai_not_configured", "Vision provider has not been configured.", 503)
