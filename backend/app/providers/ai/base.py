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


@dataclass(slots=True)
class VisionProviderResponse:
    payload: dict[str, Any]
    provider: str
    model: str
    raw_response: dict[str, Any] | None = None
    input_tokens: int | None = None
    output_tokens: int | None = None
    estimated_cost: float | None = None


class LLMProvider(Protocol):
    async def generate(self, request: AIRequest) -> AIResponse: ...


class EmbeddingProvider(Protocol):
    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class VisionProvider(Protocol):
    name: str
    model: str
    is_remote: bool

    async def analyze_meal(
        self,
        image_bytes: bytes,
        content_type: str,
        context: dict[str, Any],
    ) -> VisionProviderResponse: ...
