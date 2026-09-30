"""Phase 6 evidence-grounded knowledge, lab reports, and health AI."""

from collections.abc import Sequence

import sqlalchemy as sa
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0006_phase6_health_knowledge"
down_revision: str | None = "0005_phase5_training"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSON_TYPE = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")
EMBEDDING_TYPE = sa.JSON().with_variant(Vector(64), "postgresql")


def _identity() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    ]


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "knowledge_documents",
        sa.Column("title", sa.String(500), nullable=False),
        sa.Column("source", sa.String(120), nullable=False),
        sa.Column("source_url", sa.String(1000), nullable=True),
        sa.Column("publisher", sa.String(240), nullable=False),
        sa.Column("authors", JSON_TYPE, nullable=False),
        sa.Column("published_at", sa.Date(), nullable=True),
        sa.Column("source_updated_at", sa.Date(), nullable=True),
        sa.Column("document_version", sa.String(80), nullable=False),
        sa.Column("language", sa.String(16), nullable=False),
        sa.Column("category", sa.String(64), nullable=False),
        sa.Column("evidence_level", sa.String(32), nullable=False),
        sa.Column("document_type", sa.String(32), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("archived", sa.Boolean(), nullable=False),
        sa.Column("checksum", sa.String(64), nullable=False),
        sa.Column("content_hash", sa.String(64), nullable=False),
        sa.Column("original_file_id", sa.String(500), nullable=True),
        sa.Column("ingested_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "title",
            "publisher",
            "document_version",
            "language",
            name="uq_knowledge_document_version",
        ),
    )
    op.create_index(
        "ix_knowledge_document_active_category",
        "knowledge_documents",
        ["active", "archived", "category"],
    )
    op.create_index("ix_knowledge_document_checksum", "knowledge_documents", ["checksum"])

    op.create_table(
        "knowledge_chunks",
        sa.Column("document_id", sa.Uuid(), nullable=False),
        sa.Column("chunk_index", sa.Integer(), nullable=False),
        sa.Column("heading", sa.String(500), nullable=True),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("token_count", sa.Integer(), nullable=False),
        sa.Column("category", sa.String(64), nullable=False),
        sa.Column("content_hash", sa.String(64), nullable=False),
        sa.Column("embedding", EMBEDDING_TYPE, nullable=True),
        sa.Column("embedding_model", sa.String(160), nullable=True),
        sa.Column("metadata", JSON_TYPE, nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["document_id"], ["knowledge_documents.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("document_id", "chunk_index", name="uq_knowledge_chunk_index"),
    )
    op.create_index("ix_knowledge_chunk_document", "knowledge_chunks", ["document_id"])
    op.create_index("ix_knowledge_chunk_category", "knowledge_chunks", ["category"])
    op.create_index("ix_knowledge_chunk_content_hash", "knowledge_chunks", ["content_hash"])
    if bind.dialect.name == "postgresql":
        op.execute(
            "ALTER TABLE knowledge_chunks ADD COLUMN search_vector tsvector "
            "GENERATED ALWAYS AS "
            "(to_tsvector('simple', coalesce(heading, '') || ' ' || content)) STORED"
        )
        op.execute(
            "CREATE INDEX ix_knowledge_chunks_search_vector ON knowledge_chunks "
            "USING gin (search_vector)"
        )
        op.execute(
            "CREATE INDEX ix_knowledge_chunks_embedding_hnsw ON knowledge_chunks "
            "USING hnsw (embedding vector_cosine_ops)"
        )
        op.execute(
            "CREATE INDEX ix_knowledge_chunks_metadata_gin ON knowledge_chunks USING gin (metadata)"
        )

    op.create_table(
        "knowledge_ingestion_jobs",
        sa.Column("document_id", sa.Uuid(), nullable=True),
        sa.Column("filename", sa.String(500), nullable=False),
        sa.Column("source_type", sa.String(32), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("checksum", sa.String(64), nullable=False),
        sa.Column("stats", JSON_TYPE, nullable=False),
        sa.Column("error_summary", sa.Text(), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["document_id"], ["knowledge_documents.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_knowledge_ingestion_status", "knowledge_ingestion_jobs", ["status", "created_at"]
    )

    op.create_table(
        "lab_test_dictionary",
        sa.Column("canonical_name", sa.String(80), nullable=False),
        sa.Column("display_name", sa.String(160), nullable=False),
        sa.Column("aliases", JSON_TYPE, nullable=False),
        sa.Column("default_unit", sa.String(40), nullable=True),
        sa.Column("category", sa.String(64), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        *_identity(),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("canonical_name"),
    )

    op.create_table(
        "lab_reports",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("report_date", sa.Date(), nullable=False),
        sa.Column("hospital_name", sa.String(240), nullable=True),
        sa.Column("source_type", sa.String(24), nullable=False),
        sa.Column("original_file_id", sa.String(500), nullable=True),
        sa.Column("original_filename", sa.String(500), nullable=False),
        sa.Column("content_type", sa.String(80), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(64), nullable=False),
        sa.Column("ocr_status", sa.String(32), nullable=False),
        sa.Column("review_status", sa.String(32), nullable=False),
        sa.Column("retain_original", sa.Boolean(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_lab_report_user_date", "lab_reports", ["user_id", "report_date"])

    op.create_table(
        "lab_report_pages",
        sa.Column("report_id", sa.Uuid(), nullable=False),
        sa.Column("page_number", sa.Integer(), nullable=False),
        sa.Column("extraction_status", sa.String(32), nullable=False),
        sa.Column("text_content", sa.Text(), nullable=True),
        sa.Column("page_hash", sa.String(64), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["report_id"], ["lab_reports.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("report_id", "page_number", name="uq_lab_report_page_number"),
    )

    op.create_table(
        "lab_results",
        sa.Column("report_id", sa.Uuid(), nullable=False),
        sa.Column("test_code", sa.String(80), nullable=True),
        sa.Column("test_name", sa.String(200), nullable=False),
        sa.Column("normalized_name", sa.String(80), nullable=False),
        sa.Column("value_numeric", sa.Numeric(18, 6), nullable=True),
        sa.Column("value_text", sa.String(240), nullable=True),
        sa.Column("unit", sa.String(40), nullable=True),
        sa.Column("reference_min", sa.Numeric(18, 6), nullable=True),
        sa.Column("reference_max", sa.Numeric(18, 6), nullable=True),
        sa.Column("reference_text", sa.String(240), nullable=True),
        sa.Column("flag", sa.String(16), nullable=False),
        sa.Column("category", sa.String(64), nullable=False),
        sa.Column("confidence", sa.Numeric(5, 4), nullable=False),
        sa.Column("user_confirmed", sa.Boolean(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["report_id"], ["lab_reports.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_lab_result_report", "lab_results", ["report_id"])
    op.create_index("ix_lab_result_normalized", "lab_results", ["normalized_name"])

    op.create_table(
        "lab_ocr_sessions",
        sa.Column("report_id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(64), nullable=False),
        sa.Column("model", sa.String(160), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("remote_processing_authorized", sa.Boolean(), nullable=False),
        sa.Column("page_count", sa.Integer(), nullable=False),
        sa.Column("error_summary", sa.Text(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["report_id"], ["lab_reports.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_lab_ocr_report_status", "lab_ocr_sessions", ["report_id", "status"])

    op.create_table(
        "lab_ocr_items",
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("page_number", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("test_code", sa.String(80), nullable=True),
        sa.Column("test_name", sa.String(200), nullable=False),
        sa.Column("normalized_name", sa.String(80), nullable=False),
        sa.Column("value_numeric", sa.Numeric(18, 6), nullable=True),
        sa.Column("value_text", sa.String(240), nullable=True),
        sa.Column("unit", sa.String(40), nullable=True),
        sa.Column("reference_min", sa.Numeric(18, 6), nullable=True),
        sa.Column("reference_max", sa.Numeric(18, 6), nullable=True),
        sa.Column("reference_text", sa.String(240), nullable=True),
        sa.Column("flag", sa.String(16), nullable=False),
        sa.Column("category", sa.String(64), nullable=False),
        sa.Column("confidence", sa.Numeric(5, 4), nullable=False),
        sa.Column("user_modified", sa.Boolean(), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(["session_id"], ["lab_ocr_sessions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_lab_ocr_item_session_page", "lab_ocr_items", ["session_id", "page_number"])

    op.create_table(
        "health_ai_conversations",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(240), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_health_ai_conversation_user", "health_ai_conversations", ["user_id", "updated_at"]
    )

    op.create_table(
        "health_ai_messages",
        sa.Column("conversation_id", sa.Uuid(), nullable=False),
        sa.Column("role", sa.String(16), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("structured_payload", JSON_TYPE, nullable=False),
        sa.Column("provider", sa.String(64), nullable=False),
        sa.Column("model", sa.String(160), nullable=False),
        *_identity(),
        sa.ForeignKeyConstraint(
            ["conversation_id"], ["health_ai_conversations.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_health_ai_message_conversation", "health_ai_messages", ["conversation_id", "created_at"]
    )

    op.create_table(
        "health_check_suggestions",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("report_id", sa.Uuid(), nullable=True),
        sa.Column("suggestion_type", sa.String(64), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("suggested_after_days", sa.Integer(), nullable=True),
        sa.Column("evidence_snapshot", JSON_TYPE, nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        *_identity(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["report_id"], ["lab_reports.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_health_check_user_status", "health_check_suggestions", ["user_id", "status"]
    )


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.drop_index("ix_knowledge_chunks_metadata_gin", table_name="knowledge_chunks")
        op.drop_index("ix_knowledge_chunks_embedding_hnsw", table_name="knowledge_chunks")
        op.drop_index("ix_knowledge_chunks_search_vector", table_name="knowledge_chunks")
    for table, indexes in [
        ("health_check_suggestions", ["ix_health_check_user_status"]),
        ("health_ai_messages", ["ix_health_ai_message_conversation"]),
        ("health_ai_conversations", ["ix_health_ai_conversation_user"]),
        ("lab_ocr_items", ["ix_lab_ocr_item_session_page"]),
        ("lab_ocr_sessions", ["ix_lab_ocr_report_status"]),
        ("lab_results", ["ix_lab_result_report", "ix_lab_result_normalized"]),
        ("lab_report_pages", []),
        ("lab_reports", ["ix_lab_report_user_date"]),
        ("lab_test_dictionary", []),
        ("knowledge_ingestion_jobs", ["ix_knowledge_ingestion_status"]),
        (
            "knowledge_chunks",
            [
                "ix_knowledge_chunk_document",
                "ix_knowledge_chunk_category",
                "ix_knowledge_chunk_content_hash",
            ],
        ),
        (
            "knowledge_documents",
            ["ix_knowledge_document_active_category", "ix_knowledge_document_checksum"],
        ),
    ]:
        for index in indexes:
            op.drop_index(index, table_name=table)
        op.drop_table(table)
