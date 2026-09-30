import json
import os
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.providers.ai.embedding import MockEmbeddingProvider
from app.services.knowledge_retrieval import HybridKnowledgeRetriever

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_pgvector_jsonb_cosine_and_hybrid_retrieval() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    provider = MockEmbeddingProvider(64)
    protein_vector, sleep_vector = await provider.embed(
        [
            "protein guidance for strength training and muscle gain",
            "sleep duration and recovery guidance",
        ]
    )
    protein_document = uuid4()
    sleep_document = uuid4()
    protein_chunk = uuid4()
    sleep_chunk = uuid4()
    now = datetime.now(UTC)
    async with engine.begin() as connection:
        extension = await connection.scalar(
            text("SELECT extname FROM pg_extension WHERE extname = 'vector'")
        )
        assert extension == "vector"
        vector_type = await connection.scalar(
            text(
                "SELECT udt_name FROM information_schema.columns "
                "WHERE table_name = 'knowledge_chunks' AND column_name = 'embedding'"
            )
        )
        assert vector_type == "vector"
        metadata_type = await connection.scalar(
            text(
                "SELECT data_type FROM information_schema.columns "
                "WHERE table_name = 'knowledge_chunks' AND column_name = 'metadata'"
            )
        )
        assert metadata_type == "jsonb"
        for document_id, title, category in (
            (protein_document, "Protein Guideline", "protein"),
            (sleep_document, "Sleep Guideline", "sleep"),
        ):
            await connection.execute(
                text(
                    """
                    INSERT INTO knowledge_documents
                      (id, title, source, source_url, publisher, authors, published_at,
                       source_updated_at, document_version, language, category,
                       evidence_level, document_type, active, archived, checksum,
                       content_hash, original_file_id, ingested_at, deleted_at,
                       created_at, updated_at)
                    VALUES
                      (:id, :title, 'test', 'https://example.org', 'Test Institute',
                       CAST(:authors AS jsonb), '2026-01-01', NULL, '1', 'en', :category,
                       'guideline', 'guideline', true, false, :checksum, :content_hash,
                       NULL, :now, NULL, :now, :now)
                    """
                ),
                {
                    "id": document_id,
                    "title": title,
                    "category": category,
                    "authors": json.dumps(["Test Group"]),
                    "checksum": uuid4().hex + uuid4().hex,
                    "content_hash": uuid4().hex + uuid4().hex,
                    "now": now,
                },
            )
        for chunk_id, document_id, category, content, vector in (
            (
                protein_chunk,
                protein_document,
                "protein",
                "protein guidance for strength training and muscle gain",
                protein_vector,
            ),
            (
                sleep_chunk,
                sleep_document,
                "sleep",
                "sleep duration and recovery guidance",
                sleep_vector,
            ),
        ):
            await connection.execute(
                text(
                    """
                    INSERT INTO knowledge_chunks
                      (id, document_id, chunk_index, heading, content, token_count,
                       category, content_hash, embedding, embedding_model, metadata,
                       created_at, updated_at)
                    VALUES
                      (:id, :document_id, 0, :heading, :content, 10, :category,
                       :content_hash, CAST(:embedding AS vector), 'mock-embedding-v1',
                       CAST(:metadata AS jsonb), :now, :now)
                    """
                ),
                {
                    "id": chunk_id,
                    "document_id": document_id,
                    "heading": category.title(),
                    "content": content,
                    "category": category,
                    "content_hash": uuid4().hex + uuid4().hex,
                    "embedding": "[" + ",".join(str(value) for value in vector) + "]",
                    "metadata": json.dumps({"category": category, "source": "vetted"}),
                    "now": now,
                },
            )

        distance = await connection.scalar(
            text(
                "SELECT embedding <=> CAST(:query AS vector) FROM knowledge_chunks WHERE id = :id"
            ),
            {
                "query": "[" + ",".join(str(value) for value in protein_vector) + "]",
                "id": protein_chunk,
            },
        )
        assert float(distance) < 0.000001
        filtered = await connection.scalar(
            text("SELECT count(*) FROM knowledge_chunks WHERE metadata @> CAST(:filter AS jsonb)"),
            {"filter": json.dumps({"category": "protein"})},
        )
        assert filtered == 1

    async with AsyncSession(engine) as session:
        evidence = await HybridKnowledgeRetriever(session, provider).search(
            "protein guidance", ["protein"], limit=3
        )
        assert evidence
        assert evidence[0].document_id == protein_document
        assert evidence[0].title == "Protein Guideline"
        assert evidence[0].category == "protein"

    await engine.dispose()
