from app.core.config import Settings, get_settings
from app.providers.push.apple import ApplePushProvider
from app.providers.push.base import PushMessage, PushProvider, PushResult
from app.providers.push.mock import MockPushProvider


def build_push_provider(settings: Settings | None = None) -> PushProvider:
    current = settings or get_settings()
    if current.push_provider == "apple":
        return ApplePushProvider(current)
    return MockPushProvider()


__all__ = [
    "ApplePushProvider",
    "MockPushProvider",
    "PushMessage",
    "PushProvider",
    "PushResult",
    "build_push_provider",
]
