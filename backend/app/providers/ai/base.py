from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(slots=True)
class AIRequest:
    instructions: str
    input_text: str
    context: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class AIResponse:
    text: str
    provider: str
    model: str
    input_tokens: int = 0
    output_tokens: int = 0


class LLMProvider(Protocol):
    async def generate(self, request: AIRequest) -> AIResponse: ...


class EmbeddingProvider(Protocol):
    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class VisionProvider(Protocol):
    async def analyze_food(self, image_bytes: bytes, context: dict[str, Any]) -> dict[str, Any]: ...
