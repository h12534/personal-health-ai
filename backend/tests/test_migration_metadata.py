from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.schema import CreateIndex

from app.db.base import Base
from app.db.migration_metadata import migration_metadata


def test_postgres_metadata_contains_rag_generated_column_and_indexes() -> None:
    metadata = migration_metadata("postgresql")
    chunks = metadata.tables["knowledge_chunks"]
    assert chunks.c.search_vector.computed is not None
    assert chunks.c.search_vector.type.compile(dialect=postgresql.dialect()) == "TSVECTOR"
    indexes = {index.name: index for index in chunks.indexes}
    assert "USING hnsw (embedding vector_cosine_ops)" in str(
        CreateIndex(indexes["ix_knowledge_chunks_embedding_hnsw"]).compile(
            dialect=postgresql.dialect()
        )
    )
    assert "USING gin (search_vector)" in str(
        CreateIndex(indexes["ix_knowledge_chunks_search_vector"]).compile(
            dialect=postgresql.dialect()
        )
    )
    assert "USING gin (metadata)" in str(
        CreateIndex(indexes["ix_knowledge_chunks_metadata_gin"]).compile(
            dialect=postgresql.dialect()
        )
    )
    assert "search_vector" not in Base.metadata.tables["knowledge_chunks"].c
    assert migration_metadata("sqlite") is Base.metadata


def test_jsonb_models_match_existing_migrations_without_changing_sqlite_types() -> None:
    for table, column in (
        ("canteen_dishes", "tags"),
        ("coach_messages", "structured_payload"),
        ("daily_tasks", "reminder_policy"),
        ("exercise_library", "equipment"),
        ("sleep_logs", "sleep_stages"),
        ("health_reports", "metrics_snapshot"),
        ("training_adjustments", "evidence_snapshot"),
    ):
        data_type = Base.metadata.tables[table].c[column].type
        assert data_type.compile(dialect=postgresql.dialect()) == "JSONB"
        assert data_type.compile(dialect=sqlite.dialect()) == "JSON"
