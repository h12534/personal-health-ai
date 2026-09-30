from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Response, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_admin,
    get_current_user,
    get_embedding_provider,
    get_private_storage,
)
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.user import User
from app.providers.ai.base import EmbeddingProvider
from app.providers.storage.base import StorageProvider
from app.schemas.common import DataResponse
from app.schemas.health_knowledge import (
    EvidenceLevel,
    KnowledgeCategory,
    KnowledgeChunkRead,
    KnowledgeDocumentMetadata,
    KnowledgeDocumentRead,
    KnowledgeIngestionRead,
    KnowledgeSearchRequest,
    KnowledgeSearchResponse,
    KnowledgeStateUpdate,
)
from app.services.knowledge_ingestion_service import KnowledgeIngestionService
from app.services.knowledge_retrieval import HybridKnowledgeRetriever

router = APIRouter()


def _service(
    session: AsyncSession, embedding: EmbeddingProvider, storage: StorageProvider | None = None
) -> KnowledgeIngestionService:
    return KnowledgeIngestionService(session, embedding, storage)


@router.post(
    "/documents/import",
    response_model=DataResponse[KnowledgeIngestionRead],
    status_code=status.HTTP_201_CREATED,
)
async def import_document(
    file: UploadFile = File(...),
    title: str = Form(..., min_length=2, max_length=500),
    source: str = Form(..., min_length=2, max_length=120),
    publisher: str = Form(..., min_length=2, max_length=240),
    category: KnowledgeCategory = Form(...),
    evidence_level: EvidenceLevel = Form(...),
    document_type: str = Form(..., min_length=2, max_length=32),
    document_version: str = Form(default="1", min_length=1, max_length=80),
    language: str = Form(default="zh-CN", min_length=2, max_length=16),
    source_url: str | None = Form(default=None, max_length=1000),
    published_at: date | None = Form(default=None),
    source_updated_at: date | None = Form(default=None),
    user: User = Depends(get_current_admin),
    session: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
    embedding: EmbeddingProvider = Depends(get_embedding_provider),
    storage: StorageProvider = Depends(get_private_storage),
) -> DataResponse[KnowledgeIngestionRead]:
    data = await file.read(settings.knowledge_max_upload_bytes + 1)
    if len(data) > settings.knowledge_max_upload_bytes:
        from app.core.errors import AppError

        raise AppError("knowledge_file_too_large", "Knowledge files must be 30 MB or smaller.", 413)
    metadata = KnowledgeDocumentMetadata(
        title=title,
        source=source,
        source_url=source_url,
        publisher=publisher,
        published_at=published_at,
        source_updated_at=source_updated_at,
        document_version=document_version,
        language=language,
        category=category,
        evidence_level=evidence_level,
        document_type=document_type,
    )
    value = await KnowledgeIngestionService(
        session, embedding, storage, initiated_by_user_id=user.id
    ).ingest(
        data,
        file.filename or "knowledge.txt",
        file.content_type or "application/octet-stream",
        metadata,
    )
    return DataResponse(data=value)


@router.get("/documents", response_model=DataResponse[list[KnowledgeDocumentRead]])
async def list_documents(
    user: User = Depends(get_current_admin),
    session: AsyncSession = Depends(get_db),
    embedding: EmbeddingProvider = Depends(get_embedding_provider),
) -> DataResponse[list[KnowledgeDocumentRead]]:
    del user
    values = await _service(session, embedding).list_documents()
    return DataResponse(
        data=[KnowledgeDocumentRead.model_validate(value) for value in values],
        meta={"count": len(values)},
    )


@router.get(
    "/documents/{document_id}/chunks", response_model=DataResponse[list[KnowledgeChunkRead]]
)
async def document_chunks(
    document_id: UUID,
    user: User = Depends(get_current_admin),
    session: AsyncSession = Depends(get_db),
    embedding: EmbeddingProvider = Depends(get_embedding_provider),
) -> DataResponse[list[KnowledgeChunkRead]]:
    del user
    document = await _service(session, embedding).get(document_id)
    return DataResponse(
        data=[KnowledgeChunkRead.model_validate(value) for value in document.chunks],
        meta={"count": len(document.chunks)},
    )


@router.patch("/documents/{document_id}", response_model=DataResponse[KnowledgeDocumentRead])
async def update_document_state(
    document_id: UUID,
    payload: KnowledgeStateUpdate,
    user: User = Depends(get_current_admin),
    session: AsyncSession = Depends(get_db),
    embedding: EmbeddingProvider = Depends(get_embedding_provider),
) -> DataResponse[KnowledgeDocumentRead]:
    del user
    document = await _service(session, embedding).set_state(
        document_id, active=payload.active, archived=payload.archived
    )
    return DataResponse(data=KnowledgeDocumentRead.model_validate(document))


@router.post("/documents/{document_id}/reembed", response_model=DataResponse[KnowledgeDocumentRead])
async def reembed_document(
    document_id: UUID,
    user: User = Depends(get_current_admin),
    session: AsyncSession = Depends(get_db),
    embedding: EmbeddingProvider = Depends(get_embedding_provider),
) -> DataResponse[KnowledgeDocumentRead]:
    del user
    document = await _service(session, embedding).reembed(document_id)
    return DataResponse(data=KnowledgeDocumentRead.model_validate(document))


@router.delete("/documents/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_document(
    document_id: UUID,
    user: User = Depends(get_current_admin),
    session: AsyncSession = Depends(get_db),
    embedding: EmbeddingProvider = Depends(get_embedding_provider),
) -> Response:
    del user
    await _service(session, embedding).delete(document_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/search", response_model=DataResponse[KnowledgeSearchResponse])
async def search_knowledge(
    payload: KnowledgeSearchRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db),
    embedding: EmbeddingProvider = Depends(get_embedding_provider),
) -> DataResponse[KnowledgeSearchResponse]:
    del user
    retriever = HybridKnowledgeRetriever(session, embedding)
    evidence = await retriever.search(
        payload.query, [str(value) for value in payload.categories], payload.limit
    )
    return DataResponse(
        data=KnowledgeSearchResponse(
            evidence=evidence,
            retrieval_method=retriever.METHOD,
            threshold=retriever.threshold,
        )
    )
