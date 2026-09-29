from app.core.config import Settings, get_settings
from app.providers.ai.base import CoachProvider, VisionProvider
from app.providers.ai.disabled import DisabledAIProvider
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


__all__ = ["build_coach_provider", "build_vision_provider"]
