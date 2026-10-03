"""Complete Alembic metadata, including migration-managed PostgreSQL RAG DDL."""

from sqlalchemy import Column, Computed, Index, MetaData
from sqlalchemy.dialects.postgresql import TSVECTOR

from app.db.base import Base


def migration_metadata(dialect_name: str) -> MetaData:
    if dialect_name != "postgresql":
        return Base.metadata

    # Keep PostgreSQL-only generated columns out of SQLite's ORM create_all.
    # No reflected objects are excluded: every RAG column/index is compared.
    metadata = MetaData()
    for table in Base.metadata.sorted_tables:
        table.to_metadata(metadata)
    chunks = metadata.tables["knowledge_chunks"]
    chunks.append_column(
        Column(
            "search_vector",
            TSVECTOR(),
            Computed(
                "to_tsvector('simple', coalesce(heading, '') || ' ' || content)",
                persisted=True,
            ),
            nullable=True,
        )
    )
    Index("ix_knowledge_chunks_search_vector", chunks.c.search_vector, postgresql_using="gin")
    Index(
        "ix_knowledge_chunks_embedding_hnsw",
        chunks.c.embedding,
        postgresql_using="hnsw",
        postgresql_ops={"embedding": "vector_cosine_ops"},
    )
    Index("ix_knowledge_chunks_metadata_gin", chunks.c.metadata, postgresql_using="gin")
    return metadata
