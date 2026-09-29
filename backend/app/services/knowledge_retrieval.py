from typing import Any, Protocol


class KnowledgeRetriever(Protocol):
    async def retrieve(self, query: str, context: dict[str, Any]) -> list[dict[str, str]]: ...


class NoopKnowledgeRetriever:
    """Phase 4 seam for Phase 7 RAG; intentionally returns no invented references."""

    async def retrieve(self, query: str, context: dict[str, Any]) -> list[dict[str, str]]:
        del query, context
        return []
