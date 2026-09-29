from app.core.config import Settings, get_settings
from app.providers.ai.base import VisionProvider
from app.providers.ai.disabled import DisabledAIProvider
from app.providers.ai.mock_vision import MockVisionProvider
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


__all__ = ["build_vision_provider"]
