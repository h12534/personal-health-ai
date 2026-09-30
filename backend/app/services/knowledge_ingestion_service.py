import re
from dataclasses import dataclass
from datetime import UTC, datetime
from hashlib import sha256
from html.parser import HTMLParser
from io import BytesIO
from pathlib import Path
from uuid import UUID

from pypdf import PdfReader
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.health_knowledge import (
    KnowledgeChunk,
    KnowledgeDocument,
    KnowledgeIngestionJob,
)
from app.models.meal_analysis import AIUsageLog
from app.providers.ai.base import EmbeddingProvider
from app.providers.storage.base import StorageProvider
from app.schemas.health_knowledge import KnowledgeDocumentMetadata, KnowledgeIngestionRead


@dataclass(frozen=True, slots=True)
class ChunkDraft:
    heading: str | None
    content: str
    token_count: int


class _HTMLTextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []
        self._heading: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        del attrs
        if tag in {"h1", "h2", "h3", "h4", "p", "li", "section", "br"}:
            self.parts.append("\n")
        self._heading = tag if tag in {"h1", "h2", "h3", "h4"} else None

    def handle_endtag(self, tag: str) -> None:
        if tag in {"h1", "h2", "h3", "h4", "p", "li", "section"}:
            self.parts.append("\n")
        self._heading = None

    def handle_data(self, data: str) -> None:
        cleaned = data.strip()
        if cleaned:
            prefix = "# " if self._heading else ""
            self.parts.append(prefix + cleaned)

    def text(self) -> str:
        return " ".join(self.parts)


class DocumentExtractor:
    SUPPORTED = {".pdf", ".html", ".htm", ".md", ".markdown", ".txt"}

    @classmethod
    def extract(cls, data: bytes, filename: str) -> str:
        suffix = Path(filename).suffix.lower()
        if suffix not in cls.SUPPORTED:
            raise AppError(
                "knowledge_file_unsupported", "Supported formats: PDF, HTML, Markdown, TXT.", 415
            )
        if suffix == ".pdf":
            try:
                reader = PdfReader(BytesIO(data))
                pages = [page.extract_text() or "" for page in reader.pages]
            except Exception as exc:
                raise AppError(
                    "knowledge_pdf_invalid", "The PDF cannot be read safely.", 422
                ) from exc
            text = "\n\n".join(f"# Page {index + 1}\n{value}" for index, value in enumerate(pages))
            if len(text.strip()) < 40:
                raise AppError(
                    "knowledge_pdf_ocr_required",
                    "The PDF has no usable text layer and must enter an OCR pipeline.",
                    422,
                )
            return text
        decoded = data.decode("utf-8", errors="replace")
        if suffix in {".html", ".htm"}:
            parser = _HTMLTextExtractor()
            parser.feed(decoded)
            return parser.text()
        return decoded


class SemanticChunker:
    def __init__(
        self, min_tokens: int = 400, max_tokens: int = 900, overlap_tokens: int = 70
    ) -> None:
        self.min_tokens = min_tokens
        self.max_tokens = max_tokens
        self.overlap_tokens = overlap_tokens

    @staticmethod
    def estimate_tokens(text: str) -> int:
        latin_words = len(re.findall(r"[A-Za-z0-9]+", text))
        non_latin = len(re.findall(r"[^\x00-\x7F\s]", text))
        return max(1, latin_words + (non_latin + 1) // 2)

    def chunk(self, raw: str) -> list[ChunkDraft]:
        cleaned = self._clean(raw)
        blocks = self._blocks(cleaned)
        chunks: list[ChunkDraft] = []
        heading: str | None = None
        current: list[str] = []
        current_tokens = 0
        for kind, value in blocks:
            if kind == "heading":
                if current and current_tokens >= self.min_tokens:
                    chunks.append(self._draft(heading, current))
                    current = self._overlap(current)
                    current_tokens = self.estimate_tokens("\n\n".join(current))
                heading = value
                continue
            for paragraph in self._split_oversized(value):
                tokens = self.estimate_tokens(paragraph)
                if current and current_tokens + tokens > self.max_tokens:
                    chunks.append(self._draft(heading, current))
                    current = self._overlap(current)
                    current_tokens = self.estimate_tokens("\n\n".join(current))
                    if current and current_tokens + tokens > self.max_tokens:
                        current = []
                        current_tokens = 0
                current.append(paragraph)
                current_tokens += tokens
        if current:
            chunks.append(self._draft(heading, current))
        return [item for item in chunks if item.content.strip()]

    @staticmethod
    def _clean(raw: str) -> str:
        value = raw.replace("\x00", "").replace("\r\n", "\n").replace("\r", "\n")
        value = re.sub(r"[ \t]+", " ", value)
        return re.sub(r"\n{3,}", "\n\n", value).strip()

    @staticmethod
    def _blocks(text: str) -> list[tuple[str, str]]:
        blocks: list[tuple[str, str]] = []
        for part in re.split(r"\n\s*\n", text):
            value = part.strip()
            if not value:
                continue
            lines = value.splitlines()
            if len(lines) == 1 and re.match(r"^#{1,6}\s+", value):
                blocks.append(("heading", re.sub(r"^#{1,6}\s+", "", value)))
            elif len(value) <= 100 and value.endswith(("：", ":")):
                blocks.append(("heading", value.rstrip("：:")))
            else:
                blocks.append(("paragraph", value))
        return blocks

    def _overlap(self, paragraphs: list[str]) -> list[str]:
        kept: list[str] = []
        count = 0
        for paragraph in reversed(paragraphs):
            tokens = self.estimate_tokens(paragraph)
            if kept and count + tokens > self.overlap_tokens:
                break
            kept.insert(0, paragraph)
            count += tokens
        return kept

    def _split_oversized(self, paragraph: str) -> list[str]:
        if self.estimate_tokens(paragraph) <= self.max_tokens:
            return [paragraph]
        pieces: list[str] = []
        remaining = paragraph.strip()
        while self.estimate_tokens(remaining) > self.max_tokens:
            low, high = 1, len(remaining)
            while low < high:
                middle = (low + high + 1) // 2
                if self.estimate_tokens(remaining[:middle]) <= self.max_tokens:
                    low = middle
                else:
                    high = middle - 1
            end = low
            floor = max(1, int(end * 0.65))
            preferred = max(
                remaining.rfind(boundary, floor, end)
                for boundary in ("\n", "。", "！", "？", ".", "!", "?", ";", "；", " ")
            )
            if preferred >= floor:
                end = preferred + 1
            piece = remaining[:end].strip()
            if not piece:
                end = low
                piece = remaining[:end].strip()
            pieces.append(piece)
            remaining = remaining[end:].strip()
        if remaining:
            pieces.append(remaining)
        return pieces

    def _draft(self, heading: str | None, paragraphs: list[str]) -> ChunkDraft:
        content = "\n\n".join(paragraphs).strip()
        return ChunkDraft(heading, content, self.estimate_tokens(content))


class KnowledgeIngestionService:
    def __init__(
        self,
        session: AsyncSession,
        embedding: EmbeddingProvider,
        storage: StorageProvider | None = None,
        initiated_by_user_id: UUID | None = None,
    ) -> None:
        self.session = session
        self.embedding = embedding
        self.storage = storage
        self.initiated_by_user_id = initiated_by_user_id
        self.chunker = SemanticChunker()

    async def ingest(
        self, data: bytes, filename: str, content_type: str, metadata: KnowledgeDocumentMetadata
    ) -> KnowledgeIngestionRead:
        checksum = sha256(data).hexdigest()
        duplicate = await self.session.scalar(
            select(KnowledgeDocument).where(
                KnowledgeDocument.checksum == checksum,
                KnowledgeDocument.deleted_at.is_(None),
            )
        )
        job = KnowledgeIngestionJob(
            filename=filename,
            source_type=Path(filename).suffix.lower().lstrip("."),
            status="running",
            checksum=checksum,
            stats={},
            started_at=datetime.now(UTC),
        )
        self.session.add(job)
        if duplicate is not None:
            job.document_id = duplicate.id
            job.status = "duplicate"
            job.stats = {"chunk_count": len(duplicate.chunks)}
            job.completed_at = datetime.now(UTC)
            await self.session.commit()
            return KnowledgeIngestionRead(
                job_id=job.id,
                document=duplicate,
                chunk_count=len(duplicate.chunks),
                duplicate=True,
            )
        try:
            text = DocumentExtractor.extract(data, filename)
            drafts = self.chunker.chunk(text)
            if not drafts:
                raise AppError(
                    "knowledge_content_empty", "No usable knowledge content was found.", 422
                )
            version_conflict = await self.session.scalar(
                select(KnowledgeDocument.id).where(
                    KnowledgeDocument.title == metadata.title,
                    KnowledgeDocument.publisher == metadata.publisher,
                    KnowledgeDocument.document_version == metadata.document_version,
                    KnowledgeDocument.language == metadata.language,
                    KnowledgeDocument.deleted_at.is_(None),
                )
            )
            if version_conflict is not None:
                raise AppError(
                    "knowledge_version_conflict",
                    "This document version already exists with different content.",
                    409,
                )
            original_key = None
            if self.storage is not None:
                suffix = Path(filename).suffix.lower()
                suffix = {".htm": ".html", ".markdown": ".md"}.get(suffix, suffix)
                original_key = await self.storage.put_private(
                    data,
                    content_type,
                    suffix,
                    prefix="knowledge",
                )
            document = KnowledgeDocument(
                **metadata.model_dump(),
                active=True,
                archived=False,
                checksum=checksum,
                content_hash=sha256(text.encode("utf-8")).hexdigest(),
                original_file_id=original_key,
                ingested_at=datetime.now(UTC),
            )
            previous = list(
                (
                    await self.session.scalars(
                        select(KnowledgeDocument).where(
                            KnowledgeDocument.title == metadata.title,
                            KnowledgeDocument.publisher == metadata.publisher,
                            KnowledgeDocument.language == metadata.language,
                            KnowledgeDocument.active.is_(True),
                            KnowledgeDocument.archived.is_(False),
                            KnowledgeDocument.deleted_at.is_(None),
                        )
                    )
                ).all()
            )
            for old in previous:
                old.active = False
                old.archived = True
            hashes = [sha256(item.content.encode("utf-8")).hexdigest() for item in drafts]
            cached_rows = (
                await self.session.scalars(
                    select(KnowledgeChunk).where(
                        KnowledgeChunk.content_hash.in_(hashes),
                        KnowledgeChunk.embedding_model == self.embedding.model,
                        KnowledgeChunk.embedding.is_not(None),
                    )
                )
            ).all()
            cache = {item.content_hash: item.embedding for item in cached_rows}
            missing_indexes = [index for index, value in enumerate(hashes) if value not in cache]
            missing_vectors = await self.embedding.embed(
                [drafts[index].content for index in missing_indexes]
            )
            vectors = dict(
                zip((hashes[index] for index in missing_indexes), missing_vectors, strict=True)
            )
            for index, draft in enumerate(drafts):
                content_hash = hashes[index]
                document.chunks.append(
                    KnowledgeChunk(
                        chunk_index=index,
                        heading=draft.heading,
                        content=draft.content,
                        token_count=draft.token_count,
                        category=metadata.category,
                        content_hash=content_hash,
                        embedding=cache.get(content_hash) or vectors[content_hash],
                        embedding_model=self.embedding.model,
                        chunk_metadata={
                            "document_title": metadata.title,
                            "source": metadata.source,
                            "publisher": metadata.publisher,
                            "evidence_level": metadata.evidence_level,
                        },
                    )
                )
            self.session.add(document)
            if self.initiated_by_user_id is not None:
                self.session.add(
                    AIUsageLog(
                        user_id=self.initiated_by_user_id,
                        provider=self.embedding.name,
                        model=self.embedding.model,
                        task="embedding",
                        input_tokens=sum(item.token_count for item in drafts),
                        output_tokens=len(missing_vectors) * self.embedding.dimension,
                        image_count=0,
                        latency_ms=0,
                        status="success",
                    )
                )
            await self.session.flush()
            job.document_id = document.id
            job.status = "completed"
            job.stats = {
                "chunk_count": len(drafts),
                "token_count": sum(item.token_count for item in drafts),
                "embedding_cache_hits": len(drafts) - len(missing_indexes),
            }
            job.completed_at = datetime.now(UTC)
            await self.session.commit()
            return KnowledgeIngestionRead(
                job_id=job.id,
                document=document,
                chunk_count=len(drafts),
                duplicate=False,
            )
        except Exception as exc:
            await self.session.rollback()
            failed = KnowledgeIngestionJob(
                filename=filename,
                source_type=Path(filename).suffix.lower().lstrip("."),
                status="failed",
                checksum=checksum,
                stats={},
                error_summary=str(exc)[:500],
                started_at=job.started_at,
                completed_at=datetime.now(UTC),
            )
            self.session.add(failed)
            await self.session.commit()
            raise

    async def list_documents(self) -> list[KnowledgeDocument]:
        return list(
            (
                await self.session.scalars(
                    select(KnowledgeDocument)
                    .where(KnowledgeDocument.deleted_at.is_(None))
                    .order_by(KnowledgeDocument.created_at.desc())
                )
            )
            .unique()
            .all()
        )

    async def get(self, document_id: UUID) -> KnowledgeDocument:
        value = await self.session.scalar(
            select(KnowledgeDocument).where(
                KnowledgeDocument.id == document_id,
                KnowledgeDocument.deleted_at.is_(None),
            )
        )
        if value is None:
            raise AppError("knowledge_document_not_found", "Knowledge document was not found.", 404)
        return value

    async def set_state(
        self, document_id: UUID, *, active: bool | None, archived: bool | None
    ) -> KnowledgeDocument:
        document = await self.get(document_id)
        if active is not None:
            document.active = active
        if archived is not None:
            document.archived = archived
            if archived:
                document.active = False
        await self.session.commit()
        return document

    async def delete(self, document_id: UUID) -> None:
        document = await self.get(document_id)
        document.active = False
        document.archived = True
        document.deleted_at = datetime.now(UTC)
        await self.session.commit()

    async def reembed(self, document_id: UUID) -> KnowledgeDocument:
        document = await self.get(document_id)
        vectors = await self.embedding.embed([item.content for item in document.chunks])
        for chunk, vector in zip(document.chunks, vectors, strict=True):
            chunk.embedding = vector
            chunk.embedding_model = self.embedding.model
        await self.session.commit()
        return document
