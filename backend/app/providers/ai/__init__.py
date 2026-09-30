from app.core.config import Settings, get_settings
from app.providers.ai.base import (
    CoachProvider,
    EmbeddingProvider,
    HealthAnswerProvider,
    LabOCRProvider,
    VisionProvider,
)
from app.providers.ai.disabled import DisabledAIProvider
from app.providers.ai.embedding import MockEmbeddingProvider, OpenAICompatibleEmbeddingProvider
from app.providers.ai.health_answer import (
    MockHealthAnswerProvider,
    OpenAICompatibleHealthAnswerProvider,
)
from app.providers.ai.lab_ocr import MockLabOCRProvider, OpenAICompatibleLabOCRProvider
from app.providers.ai.mock_coach import MockCoachProvider
from app.providers.ai.mock_vision import MockVisionProvider
from app.providers.ai.openai_compatible_coach import OpenAICompatibleCoachProvider
from app.providers.ai.openai_compatible_vision import OpenAICompatibleVisionProvider


def build_vision_provider(settings: Settings | None = None) -> VisionProvider:
    config = settings or get_settings()
    if config.vision_provider == "mock":
        return MockVisionProvider()
    if config.vision_provider == "openai_compatible":
        assert config.vision_base_url is not None
        assert config.vision_api_key is not None
        return OpenAICompatibleVisionProvider(
            base_url=config.vision_base_url,
            api_key=config.vision_api_key,
            model=config.vision_model,
            timeout_seconds=config.vision_timeout_seconds,
            max_attempts=config.vision_max_attempts,
        )
    return DisabledAIProvider()


def build_coach_provider(settings: Settings | None = None) -> CoachProvider:
    config = settings or get_settings()
    if config.coach_provider == "openai_compatible":
        assert config.coach_base_url is not None
        assert config.coach_api_key is not None
        return OpenAICompatibleCoachProvider(
            base_url=config.coach_base_url,
            api_key=config.coach_api_key,
            model=config.coach_model,
            timeout_seconds=config.coach_timeout_seconds,
            max_attempts=config.coach_max_attempts,
        )
    return MockCoachProvider()


def build_embedding_provider(settings: Settings | None = None) -> EmbeddingProvider:
    config = settings or get_settings()
    if config.embedding_provider == "openai_compatible":
        assert config.embedding_base_url is not None
        assert config.embedding_api_key is not None
        return OpenAICompatibleEmbeddingProvider(
            base_url=config.embedding_base_url,
            api_key=config.embedding_api_key,
            model=config.embedding_model,
            dimension=config.embedding_dimension,
            timeout_seconds=config.embedding_timeout_seconds,
        )
    return MockEmbeddingProvider(config.embedding_dimension)


def build_lab_ocr_provider(settings: Settings | None = None) -> LabOCRProvider:
    config = settings or get_settings()
    if config.lab_ocr_provider == "openai_compatible":
        assert config.lab_ocr_base_url is not None
        assert config.lab_ocr_api_key is not None
        return OpenAICompatibleLabOCRProvider(
            base_url=config.lab_ocr_base_url,
            api_key=config.lab_ocr_api_key,
            model=config.lab_ocr_model,
            timeout_seconds=config.lab_ocr_timeout_seconds,
        )
    return MockLabOCRProvider()


def build_health_answer_provider(settings: Settings | None = None) -> HealthAnswerProvider:
    config = settings or get_settings()
    if config.health_answer_provider == "openai_compatible":
        assert config.health_answer_base_url is not None
        assert config.health_answer_api_key is not None
        return OpenAICompatibleHealthAnswerProvider(
            base_url=config.health_answer_base_url,
            api_key=config.health_answer_api_key,
            model=config.health_answer_model,
            timeout_seconds=config.health_answer_timeout_seconds,
        )
    return MockHealthAnswerProvider()


__all__ = [
    "build_coach_provider",
    "build_embedding_provider",
    "build_health_answer_provider",
    "build_lab_ocr_provider",
    "build_vision_provider",
]
