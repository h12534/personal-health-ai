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


@dataclass(slots=True)
class CoachProviderResponse:
    payload: dict[str, Any]
    provider: str
    model: str
    input_tokens: int | None = None
    output_tokens: int | None = None


class LLMProvider(Protocol):
    async def generate(self, request: AIRequest) -> AIResponse: ...


class EmbeddingProvider(Protocol):
    name: str
    model: str
    dimension: int
    is_remote: bool

    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class LabOCRProvider(Protocol):
    name: str
    model: str
    is_remote: bool

    async def analyze_page(
        self,
        page_bytes: bytes,
        content_type: str,
        page_number: int,
    ) -> list[dict[str, Any]]: ...


@dataclass(slots=True)
class HealthAnswerProviderResponse:
    answer: str
    provider: str
    model: str
    input_tokens: int | None = None
    output_tokens: int | None = None


class HealthAnswerProvider(Protocol):
    name: str
    model: str

    async def answer(
        self,
        message: str,
        intent: str,
        context: dict[str, Any],
        evidence: list[dict[str, Any]],
    ) -> HealthAnswerProviderResponse: ...


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


class CoachProvider(Protocol):
    name: str
    model: str

    async def respond(
        self, message: str, intent: str, context: dict[str, Any]
    ) -> CoachProviderResponse: ...
