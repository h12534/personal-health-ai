from datetime import date, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin

JSON_TYPE = JSON().with_variant(JSONB(), "postgresql")
EMBEDDING_TYPE = JSON().with_variant(Vector(64), "postgresql")


class KnowledgeDocument(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "knowledge_documents"
    __table_args__ = (
        UniqueConstraint(
            "title",
            "publisher",
            "document_version",
            "language",
            name="uq_knowledge_document_version",
        ),
        Index("ix_knowledge_document_active_category", "active", "archived", "category"),
        Index("ix_knowledge_document_checksum", "checksum"),
    )

    title: Mapped[str] = mapped_column(String(500), nullable=False)
    source: Mapped[str] = mapped_column(String(120), nullable=False)
    source_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    publisher: Mapped[str] = mapped_column(String(240), nullable=False)
    authors: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    published_at: Mapped[date | None] = mapped_column(Date, nullable=True)
    source_updated_at: Mapped[date | None] = mapped_column(Date, nullable=True)
    document_version: Mapped[str] = mapped_column(String(80), nullable=False)
    language: Mapped[str] = mapped_column(String(16), default="zh-CN")
    category: Mapped[str] = mapped_column(String(64), nullable=False)
    evidence_level: Mapped[str] = mapped_column(String(32), nullable=False)
    document_type: Mapped[str] = mapped_column(String(32), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)
    checksum: Mapped[str] = mapped_column(String(64), nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    original_file_id: Mapped[str | None] = mapped_column(String(500), nullable=True)
    ingested_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    chunks: Mapped[list["KnowledgeChunk"]] = relationship(
        back_populates="document", cascade="all, delete-orphan", lazy="selectin"
    )


class KnowledgeChunk(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "knowledge_chunks"
    __table_args__ = (
        UniqueConstraint("document_id", "chunk_index", name="uq_knowledge_chunk_index"),
        Index("ix_knowledge_chunk_document", "document_id"),
        Index("ix_knowledge_chunk_category", "category"),
        Index("ix_knowledge_chunk_content_hash", "content_hash"),
    )

    document_id: Mapped[UUID] = mapped_column(
        ForeignKey("knowledge_documents.id", ondelete="CASCADE")
    )
    chunk_index: Mapped[int] = mapped_column(Integer, nullable=False)
    heading: Mapped[str | None] = mapped_column(String(500), nullable=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    token_count: Mapped[int] = mapped_column(Integer, nullable=False)
    category: Mapped[str] = mapped_column(String(64), nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    embedding: Mapped[list[float] | None] = mapped_column(EMBEDDING_TYPE, nullable=True)
    embedding_model: Mapped[str | None] = mapped_column(String(160), nullable=True)
    chunk_metadata: Mapped[dict[str, Any]] = mapped_column("metadata", JSON_TYPE, default=dict)

    document: Mapped[KnowledgeDocument] = relationship(back_populates="chunks")


class KnowledgeIngestionJob(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "knowledge_ingestion_jobs"
    __table_args__ = (Index("ix_knowledge_ingestion_status", "status", "created_at"),)

    document_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("knowledge_documents.id", ondelete="SET NULL"), nullable=True
    )
    filename: Mapped[str] = mapped_column(String(500), nullable=False)
    source_type: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="pending")
    checksum: Mapped[str] = mapped_column(String(64), nullable=False)
    stats: Mapped[dict[str, Any]] = mapped_column(JSON_TYPE, default=dict)
    error_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class LabTestDictionary(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "lab_test_dictionary"

    canonical_name: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)
    display_name: Mapped[str] = mapped_column(String(160), nullable=False)
    aliases: Mapped[list[str]] = mapped_column(JSON_TYPE, default=list)
    default_unit: Mapped[str | None] = mapped_column(String(40), nullable=True)
    category: Mapped[str] = mapped_column(String(64), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class LabReport(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "lab_reports"
    __table_args__ = (Index("ix_lab_report_user_date", "user_id", "report_date"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    report_date: Mapped[date] = mapped_column(Date, nullable=False)
    hospital_name: Mapped[str | None] = mapped_column(String(240), nullable=True)
    source_type: Mapped[str] = mapped_column(String(24), nullable=False)
    original_file_id: Mapped[str | None] = mapped_column(String(500), nullable=True)
    original_filename: Mapped[str] = mapped_column(String(500), nullable=False)
    content_type: Mapped[str] = mapped_column(String(80), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    ocr_status: Mapped[str] = mapped_column(String(32), default="pending")
    review_status: Mapped[str] = mapped_column(String(32), default="draft")
    retain_original: Mapped[bool] = mapped_column(Boolean, default=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    pages: Mapped[list["LabReportPage"]] = relationship(
        back_populates="report", cascade="all, delete-orphan", lazy="selectin"
    )
    results: Mapped[list["LabResult"]] = relationship(
        back_populates="report", cascade="all, delete-orphan", lazy="selectin"
    )
    ocr_sessions: Mapped[list["LabOCRSession"]] = relationship(
        back_populates="report", cascade="all, delete-orphan", lazy="selectin"
    )


class LabReportPage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "lab_report_pages"
    __table_args__ = (
        UniqueConstraint("report_id", "page_number", name="uq_lab_report_page_number"),
    )

    report_id: Mapped[UUID] = mapped_column(ForeignKey("lab_reports.id", ondelete="CASCADE"))
    page_number: Mapped[int] = mapped_column(Integer, nullable=False)
    extraction_status: Mapped[str] = mapped_column(String(32), default="pending")
    text_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    page_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    report: Mapped[LabReport] = relationship(back_populates="pages")


class LabResult(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "lab_results"
    __table_args__ = (
        Index("ix_lab_result_report", "report_id"),
        Index("ix_lab_result_normalized", "normalized_name"),
    )

    report_id: Mapped[UUID] = mapped_column(ForeignKey("lab_reports.id", ondelete="CASCADE"))
    test_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
    test_name: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(80), nullable=False)
    value_numeric: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
    value_text: Mapped[str | None] = mapped_column(String(240), nullable=True)
    unit: Mapped[str | None] = mapped_column(String(40), nullable=True)
    reference_min: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
    reference_max: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
    reference_text: Mapped[str | None] = mapped_column(String(240), nullable=True)
    flag: Mapped[str] = mapped_column(String(16), default="unknown")
    category: Mapped[str] = mapped_column(String(64), nullable=False)
    confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4), nullable=False)
    user_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    report: Mapped[LabReport] = relationship(back_populates="results")


class LabOCRSession(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "lab_ocr_sessions"
    __table_args__ = (Index("ix_lab_ocr_report_status", "report_id", "status"),)

    report_id: Mapped[UUID] = mapped_column(ForeignKey("lab_reports.id", ondelete="CASCADE"))
    provider: Mapped[str] = mapped_column(String(64), nullable=False)
    model: Mapped[str] = mapped_column(String(160), nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="pending")
    remote_processing_authorized: Mapped[bool] = mapped_column(Boolean, default=False)
    page_count: Mapped[int] = mapped_column(Integer, default=1)
    error_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    report: Mapped[LabReport] = relationship(back_populates="ocr_sessions")
    items: Mapped[list["LabOCRItem"]] = relationship(
        back_populates="session", cascade="all, delete-orphan", lazy="selectin"
    )


class LabOCRItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "lab_ocr_items"
    __table_args__ = (Index("ix_lab_ocr_item_session_page", "session_id", "page_number"),)

    session_id: Mapped[UUID] = mapped_column(ForeignKey("lab_ocr_sessions.id", ondelete="CASCADE"))
    page_number: Mapped[int] = mapped_column(Integer, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    test_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
    test_name: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(80), nullable=False)
    value_numeric: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
    value_text: Mapped[str | None] = mapped_column(String(240), nullable=True)
    unit: Mapped[str | None] = mapped_column(String(40), nullable=True)
    reference_min: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
    reference_max: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
    reference_text: Mapped[str | None] = mapped_column(String(240), nullable=True)
    flag: Mapped[str] = mapped_column(String(16), default="unknown")
    category: Mapped[str] = mapped_column(String(64), nullable=False)
    confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4), nullable=False)
    user_modified: Mapped[bool] = mapped_column(Boolean, default=False)

    session: Mapped[LabOCRSession] = relationship(back_populates="items")


class HealthAIConversation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "health_ai_conversations"
    __table_args__ = (Index("ix_health_ai_conversation_user", "user_id", "updated_at"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str | None] = mapped_column(String(240), nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    messages: Mapped[list["HealthAIMessage"]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan", lazy="selectin"
    )


class HealthAIMessage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "health_ai_messages"
    __table_args__ = (Index("ix_health_ai_message_conversation", "conversation_id", "created_at"),)

    conversation_id: Mapped[UUID] = mapped_column(
        ForeignKey("health_ai_conversations.id", ondelete="CASCADE")
    )
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    structured_payload: Mapped[dict[str, Any]] = mapped_column(JSON_TYPE, default=dict)
    provider: Mapped[str] = mapped_column(String(64), nullable=False)
    model: Mapped[str] = mapped_column(String(160), nullable=False)

    conversation: Mapped[HealthAIConversation] = relationship(back_populates="messages")


class HealthCheckSuggestion(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "health_check_suggestions"
    __table_args__ = (Index("ix_health_check_user_status", "user_id", "status"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    report_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("lab_reports.id", ondelete="SET NULL"), nullable=True
    )
    suggestion_type: Mapped[str] = mapped_column(String(64), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    suggested_after_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    evidence_snapshot: Mapped[dict[str, Any]] = mapped_column(JSON_TYPE, default=dict)
    status: Mapped[str] = mapped_column(String(24), default="suggested")
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
