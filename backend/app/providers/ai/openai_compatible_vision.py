import asyncio
import base64
import json
from typing import Any

import httpx

from app.ai.prompts import MEAL_PROMPT
from app.core.errors import AppError
from app.providers.ai.base import VisionProviderResponse
from app.schemas.meal_analysis import VisionMealResult


class OpenAICompatibleVisionProvider:
    name = "openai_compatible"
    is_remote = True

    def __init__(
        self,
        base_url: str,
        api_key: str,
        model: str,
        timeout_seconds: int,
        max_attempts: int,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.max_attempts = max_attempts

    async def analyze_meal(
        self, image_bytes: bytes, content_type: str, context: dict[str, Any]
    ) -> VisionProviderResponse:
        encoded = base64.b64encode(image_bytes).decode("ascii")
        body = {
            "model": self.model,
            "temperature": 0,
            "messages": [
                {"role": "system", "content": MEAL_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Context: " + json.dumps(context, ensure_ascii=False),
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{content_type};base64,{encoded}",
                                "detail": "high",
                            },
                        },
                    ],
                },
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "meal_analysis",
                    "strict": True,
                    "schema": VisionMealResult.model_json_schema(),
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
                content = raw["choices"][0]["message"]["content"]
                payload = json.loads(content) if isinstance(content, str) else content
                usage = raw.get("usage") or {}
                return VisionProviderResponse(
                    payload=payload,
                    raw_response=raw,
                    provider=self.name,
                    model=self.model,
                    input_tokens=usage.get("prompt_tokens"),
                    output_tokens=usage.get("completion_tokens"),
                )
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
                "vision_timeout", "Meal analysis timed out. Please retry.", 504
            ) from last_error
        raise AppError(
            "vision_provider_error",
            "The vision provider could not analyze this image.",
            502,
        ) from last_error
