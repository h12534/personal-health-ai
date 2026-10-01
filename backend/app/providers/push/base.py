from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class PushMessage:
    token: str
    title: str
    body: str
    category: str
    data: dict[str, str]


@dataclass(frozen=True)
class PushResult:
    accepted: bool
    provider_message_id: str | None = None
    error: str | None = None


class PushProvider(Protocol):
    name: str

    async def send(self, message: PushMessage) -> PushResult: ...
