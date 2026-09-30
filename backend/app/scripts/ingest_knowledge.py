import argparse
import asyncio
from datetime import date
from pathlib import Path

from app.db.session import SessionLocal
from app.providers.ai import build_embedding_provider
from app.providers.storage import get_storage_provider
from app.schemas.health_knowledge import KnowledgeDocumentMetadata
from app.services.knowledge_ingestion_service import KnowledgeIngestionService


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Ingest a vetted health knowledge document.")
    parser.add_argument("file", type=Path)
    parser.add_argument("--title", required=True)
    parser.add_argument("--category", required=True)
    parser.add_argument("--evidence-level", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--publisher", required=True)
    parser.add_argument("--source-url")
    parser.add_argument("--published-at", type=date.fromisoformat)
    parser.add_argument("--document-version", default="1")
    parser.add_argument("--document-type", default="guideline")
    parser.add_argument("--language", default="zh-CN")
    return parser


async def _run(args: argparse.Namespace) -> None:
    data = args.file.read_bytes()
    metadata = KnowledgeDocumentMetadata(
        title=args.title,
        source=args.source,
        source_url=args.source_url,
        publisher=args.publisher,
        published_at=args.published_at,
        document_version=args.document_version,
        language=args.language,
        category=args.category,
        evidence_level=args.evidence_level,
        document_type=args.document_type,
    )
    async with SessionLocal() as session:
        result = await KnowledgeIngestionService(
            session, build_embedding_provider(), get_storage_provider()
        ).ingest(data, args.file.name, "application/octet-stream", metadata)
    print(f"document={result.document.id} chunks={result.chunk_count} duplicate={result.duplicate}")


def main() -> None:
    asyncio.run(_run(_parser().parse_args()))


if __name__ == "__main__":
    main()
