import math
import re
from dataclasses import dataclass
from datetime import date
from typing import Any, Protocol
from uuid import UUID

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.health_knowledge import KnowledgeChunk, KnowledgeDocument
from app.providers.ai.base import EmbeddingProvider
from app.schemas.health_knowledge import RetrievalEvidence


@dataclass(slots=True)
class RetrievalCandidate:
    chunk_id: UUID
    document_id: UUID
    title: str
    publisher: str
    published_at: date | None
    heading: str | None
    source_url: str | None
    content: str
    category: str
    evidence_level: str
    vector_score: float
    text_score: float
    score: float = 0.0


class Reranker(Protocol):
    def rerank(
        self, query: str, candidates: list[RetrievalCandidate]
    ) -> list[RetrievalCandidate]: ...


class DeterministicReranker:
    EVIDENCE_BOOST = {
        "guideline": 0.10,
        "systematic_review": 0.09,
        "meta_analysis": 0.09,
        "randomized_trial": 0.07,
        "expert_consensus": 0.05,
        "review": 0.04,
        "observational": 0.02,
        "general_reference": 0.01,
    }

    def rerank(self, query: str, candidates: list[RetrievalCandidate]) -> list[RetrievalCandidate]:
        normalized = query.lower()
        for item in candidates:
            heading_boost = (
                0.05
                if item.heading
                and any(token in item.heading.lower() for token in self._tokens(normalized))
                else 0.0
            )
            item.score = min(
                1.0,
                item.vector_score * 0.55
                + item.text_score * 0.35
                + self.EVIDENCE_BOOST.get(item.evidence_level, 0.0)
                + heading_boost,
            )
        return sorted(candidates, key=lambda value: value.score, reverse=True)

    @staticmethod
    def _tokens(value: str) -> set[str]:
        words = set(re.findall(r"[a-z0-9]{2,}|[\u4e00-\u9fff]{2,}", value))
        chinese = "".join(re.findall(r"[\u4e00-\u9fff]", value))
        words.update(chinese[index : index + 2] for index in range(max(0, len(chinese) - 1)))
        return {word for word in words if word}


class HybridKnowledgeRetriever:
    METHOD = "pgvector_fts_rrf_v1"

    def __init__(
        self,
        session: AsyncSession,
        embedding: EmbeddingProvider,
        reranker: Reranker | None = None,
        threshold: float = 0.18,
    ) -> None:
        self.session = session
        self.embedding = embedding
        self.reranker = reranker or DeterministicReranker()
        self.threshold = threshold

    async def search(
        self, query: str, categories: list[str] | None = None, limit: int = 6
    ) -> list[RetrievalEvidence]:
        query_vector = (await self.embedding.embed([query]))[0]
        if self.session.bind and self.session.bind.dialect.name == "postgresql":
            candidates = await self._postgres_candidates(query, query_vector, categories or [])
        else:
            candidates = await self._portable_candidates(query, query_vector, categories or [])
        ranked = self.reranker.rerank(query, candidates)
        return [self._evidence(item) for item in ranked if item.score >= self.threshold][:limit]

    async def retrieve(self, query: str, context: dict[str, Any]) -> list[dict[str, str]]:
        categories = context.get("categories")
        category_values = (
            [str(value) for value in categories] if isinstance(categories, list) else []
        )
        values = await self.search(query, category_values)
        return [
            {
                "title": item.title,
                "publisher": item.publisher,
                "source_url": item.source_url or "",
                "excerpt": item.excerpt,
            }
            for item in values
        ]

    async def _portable_candidates(
        self, query: str, vector: list[float], categories: list[str]
    ) -> list[RetrievalCandidate]:
        statement = (
            select(KnowledgeChunk, KnowledgeDocument)
            .join(KnowledgeDocument, KnowledgeDocument.id == KnowledgeChunk.document_id)
            .where(
                KnowledgeDocument.active.is_(True),
                KnowledgeDocument.archived.is_(False),
                KnowledgeDocument.deleted_at.is_(None),
            )
        )
        if categories:
            statement = statement.where(KnowledgeChunk.category.in_(categories))
        rows = (await self.session.execute(statement.limit(500))).all()
        query_tokens = DeterministicReranker._tokens(query.lower())
        values: list[RetrievalCandidate] = []
        for chunk, document in rows:
            content_tokens = DeterministicReranker._tokens(
                f"{chunk.heading or ''} {chunk.content}".lower()
            )
            overlap = len(query_tokens & content_tokens)
            text_score = overlap / max(1, len(query_tokens))
            embedding = [float(value) for value in (chunk.embedding or [])]
            values.append(
                RetrievalCandidate(
                    chunk_id=chunk.id,
                    document_id=document.id,
                    title=document.title,
                    publisher=document.publisher,
                    published_at=document.published_at,
                    heading=chunk.heading,
                    source_url=document.source_url,
                    content=chunk.content,
                    category=chunk.category,
                    evidence_level=document.evidence_level,
                    vector_score=self._cosine(vector, embedding),
                    text_score=min(1.0, text_score),
                )
            )
        return values

    async def _postgres_candidates(
        self, query: str, vector: list[float], categories: list[str]
    ) -> list[RetrievalCandidate]:
        category_filter = "AND kc.category = ANY(CAST(:categories AS text[]))" if categories else ""
        statement = text(
            f"""
            SELECT kc.id AS chunk_id, kd.id AS document_id, kd.title, kd.publisher,
                   kd.published_at, kc.heading, kd.source_url, kc.content, kc.category,
                   kd.evidence_level,
                   GREATEST(0, 1 - (kc.embedding <=> CAST(:embedding AS vector))) AS vector_score,
                   LEAST(1, ts_rank_cd(kc.search_vector, plainto_tsquery('simple', :query)) * 4)
                     AS text_score
            FROM knowledge_chunks kc
            JOIN knowledge_documents kd ON kd.id = kc.document_id
            WHERE kd.active = true AND kd.archived = false AND kd.deleted_at IS NULL
              AND kc.embedding IS NOT NULL {category_filter}
            ORDER BY (kc.embedding <=> CAST(:embedding AS vector)) ASC
            LIMIT 80
            """
        )
        params: dict[str, object] = {
            "query": query,
            "embedding": "[" + ",".join(f"{value:.8f}" for value in vector) + "]",
        }
        if categories:
            params["categories"] = categories
        rows = (await self.session.execute(statement, params)).mappings().all()
        return [
            RetrievalCandidate(
                chunk_id=row["chunk_id"],
                document_id=row["document_id"],
                title=row["title"],
                publisher=row["publisher"],
                published_at=row["published_at"],
                heading=row["heading"],
                source_url=row["source_url"],
                content=row["content"],
                category=row["category"],
                evidence_level=row["evidence_level"],
                vector_score=float(row["vector_score"] or 0),
                text_score=float(row["text_score"] or 0),
            )
            for row in rows
        ]

    @staticmethod
    def _cosine(left: list[float], right: list[float]) -> float:
        if not left or len(left) != len(right):
            return 0.0
        dot = sum(a * b for a, b in zip(left, right, strict=True))
        denominator = math.sqrt(sum(a * a for a in left)) * math.sqrt(
            sum(value * value for value in right)
        )
        return max(0.0, min(1.0, dot / denominator if denominator else 0.0))

    @staticmethod
    def _evidence(item: RetrievalCandidate) -> RetrievalEvidence:
        excerpt = re.sub(r"\s+", " ", item.content).strip()
        if len(excerpt) > 360:
            excerpt = excerpt[:357].rstrip() + "..."
        return RetrievalEvidence(
            document_id=item.document_id,
            title=item.title,
            publisher=item.publisher,
            year=item.published_at.year if item.published_at else None,
            chunk_id=item.chunk_id,
            heading=item.heading,
            source_url=item.source_url,
            excerpt=excerpt,
            score=round(item.score, 4),
            category=item.category,
            evidence_level=item.evidence_level,
        )


class KnowledgeRetriever(Protocol):
    async def retrieve(self, query: str, context: dict[str, Any]) -> list[dict[str, str]]: ...


class NoopKnowledgeRetriever:
    async def retrieve(self, query: str, context: dict[str, Any]) -> list[dict[str, str]]:
        del query, context
        return []
