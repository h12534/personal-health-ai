import asyncio
import json
from typing import Any

import httpx

from app.ai.prompts import DIET_COACH_PROMPT
from app.core.errors import AppError
from app.providers.ai.base import CoachProviderResponse
from app.schemas.diet_coach import CoachGeneratedReply


class OpenAICompatibleCoachProvider:
    name = "openai_compatible"

    def __init__(
        self, base_url: str, api_key: str, model: str, timeout_seconds: int, max_attempts: int
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.max_attempts = max_attempts

    async def respond(
        self, message: str, intent: str, context: dict[str, Any]
    ) -> CoachProviderResponse:
        body = {
            "model": self.model,
            "temperature": 0.2,
            "messages": [
                {"role": "system", "content": DIET_COACH_PROMPT},
                {
                    "role": "user",
                    "content": json.dumps(
                        {"intent": intent, "message": message, "context": context},
                        ensure_ascii=False,
                    ),
                },
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "diet_coach_reply",
                    "strict": True,
                    "schema": CoachGeneratedReply.model_json_schema(),
                },
            },
        }
        last_error: Exception | None = None
        for attempt in range(self.max_attempts):
            try:
                async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                    response = await client.post(
                        f"{self.base_url}/chat/completions",
                        headers={"Authorization": f"Bearer {self.api_key}"},
                        json=body,
                    )
                response.raise_for_status()
                raw = response.json()
                message_data = raw["choices"][0]["message"]
                if message_data.get("refusal"):
                    raise AppError(
                        "coach_refusal", "The coach provider declined this request.", 422
                    )
                content = message_data["content"]
                payload = json.loads(content) if isinstance(content, str) else content
                validated = CoachGeneratedReply.model_validate(payload)
                usage = raw.get("usage") or {}
                return CoachProviderResponse(
                    payload=validated.model_dump(mode="json"),
                    provider=self.name,
                    model=self.model,
                    input_tokens=usage.get("prompt_tokens"),
                    output_tokens=usage.get("completion_tokens"),
                )
            except AppError:
                raise
            except (httpx.TimeoutException, httpx.TransportError) as exc:
                last_error = exc
                if attempt + 1 < self.max_attempts:
                    await asyncio.sleep(0.25 * (attempt + 1))
                    continue
            except (
                httpx.HTTPStatusError,
                KeyError,
                TypeError,
                ValueError,
                json.JSONDecodeError,
            ) as exc:
                last_error = exc
                break
        if isinstance(last_error, httpx.TimeoutException):
            raise AppError(
                "coach_timeout", "The AI coach timed out. Please retry.", 504
            ) from last_error
        raise AppError(
            "coach_provider_error", "The AI coach provider is unavailable.", 502
        ) from last_error
