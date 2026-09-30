import math
from hashlib import sha256

import httpx

from app.core.errors import AppError


class MockEmbeddingProvider:
    name = "mock"
    model = "mock-embedding-v1"
    is_remote = False

    def __init__(self, dimension: int = 64) -> None:
        self.dimension = dimension

    async def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._embed_one(text) for text in texts]

    def _embed_one(self, text: str) -> list[float]:
        values = [0.0] * self.dimension
        normalized = "".join(text.lower().split())
        features = [normalized[index : index + 2] for index in range(max(1, len(normalized) - 1))]
        if not features:
            features = ["empty"]
        for feature in features:
            digest = sha256(feature.encode("utf-8")).digest()
            index = int.from_bytes(digest[:4], "big") % self.dimension
            sign = 1.0 if digest[4] % 2 == 0 else -1.0
            values[index] += sign
        norm = math.sqrt(sum(value * value for value in values)) or 1.0
        return [value / norm for value in values]


class OpenAICompatibleEmbeddingProvider:
    name = "openai_compatible"
    is_remote = True

    def __init__(
        self,
        *,
        base_url: str,
        api_key: str,
        model: str,
        dimension: int,
        timeout_seconds: int,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        self.dimension = dimension
        self.timeout_seconds = timeout_seconds

    async def embed(self, texts: list[str]) -> list[list[float]]:
        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                response = await client.post(
                    f"{self.base_url}/embeddings",
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    json={"model": self.model, "input": texts, "dimensions": self.dimension},
                )
                response.raise_for_status()
        except httpx.HTTPError as exc:
            raise AppError("embedding_provider_error", "Embedding provider failed.", 502) from exc
        payload = response.json()
        vectors = [
            item["embedding"] for item in sorted(payload["data"], key=lambda item: item["index"])
        ]
        if len(vectors) != len(texts) or any(len(vector) != self.dimension for vector in vectors):
            raise AppError(
                "embedding_shape_invalid", "Embedding provider returned invalid data.", 502
            )
        return [[float(value) for value in vector] for vector in vectors]
