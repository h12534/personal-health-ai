from hashlib import sha256

from app.providers.push.base import PushMessage, PushResult


class MockPushProvider:
    name = "mock"

    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.messages: list[PushMessage] = []

    async def send(self, message: PushMessage) -> PushResult:
        self.messages.append(message)
        if self.fail:
            return PushResult(accepted=False, error="mock_failure")
        message_id = sha256(
            f"{message.token}:{message.category}:{len(self.messages)}".encode()
        ).hexdigest()[:24]
        return PushResult(accepted=True, provider_message_id=message_id)
