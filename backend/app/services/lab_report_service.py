from datetime import UTC, date, datetime
from decimal import Decimal
from hashlib import sha256
from io import BytesIO
from pathlib import Path
from time import perf_counter
from typing import Any
from uuid import UUID

from PIL import Image, UnidentifiedImageError
from pypdf import PdfReader, PdfWriter
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import Settings
from app.core.errors import AppError
from app.models.health_knowledge import (
    LabOCRItem,
    LabOCRSession,
    LabReport,
    LabReportPage,
    LabResult,
    LabTestDictionary,
)
from app.models.meal_analysis import AIUsageLog
from app.providers.ai.base import LabOCRProvider
from app.providers.storage.base import StorageProvider
from app.schemas.health_knowledge import (
    LabConfirmRequest,
    LabOCRItemPatch,
    LabOCRItemRead,
    LabReportRead,
    LabResultRead,
    LabTrendPoint,
    LabTrendRead,
)
from app.services.lab_unit_conversion_service import LabUnitConversionService

REPORT_LOAD = (
    selectinload(LabReport.ocr_sessions).selectinload(LabOCRSession.items),
    selectinload(LabReport.results),
    selectinload(LabReport.pages),
)


class LabDocumentProcessor:
    ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "application/pdf"}

    @classmethod
    def validate(cls, data: bytes, content_type: str) -> None:
        if not data:
            raise AppError("empty_lab_report", "Please choose a non-empty lab report.", 422)
        if content_type not in cls.ALLOWED_TYPES:
            raise AppError("lab_report_type_unsupported", "Use JPEG, PNG, WEBP, or PDF.", 415)
        if content_type == "application/pdf":
            if not data.startswith(b"%PDF-"):
                raise AppError("invalid_lab_pdf", "The selected PDF is invalid.", 422)
            return
        signatures = {
            "image/jpeg": data.startswith(b"\xff\xd8\xff"),
            "image/png": data.startswith(b"\x89PNG\r\n\x1a\n"),
            "image/webp": len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP",
        }
        if not signatures.get(content_type, False):
            raise AppError("invalid_lab_image", "The selected image is invalid.", 422)
        try:
            with Image.open(BytesIO(data)) as image:
                image.verify()
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            raise AppError("invalid_lab_image", "The selected image is invalid.", 422) from exc

    @classmethod
    def pages(cls, data: bytes, content_type: str) -> list[tuple[bytes, str, str | None]]:
        if content_type != "application/pdf":
            return [(data, content_type, None)]
        try:
            import fitz  # type: ignore[import-untyped]

            document = fitz.open(stream=data, filetype="pdf")
            values: list[tuple[bytes, str, str | None]] = []
            for page in document:
                text = page.get_text("text").strip()
                if len(text) >= 20:
                    values.append((text.encode("utf-8"), "text/plain", text))
                else:
                    pixmap = page.get_pixmap(matrix=fitz.Matrix(1.6, 1.6), alpha=False)
                    values.append((pixmap.tobytes("png"), "image/png", None))
            document.close()
            return values
        except ImportError:
            reader = PdfReader(BytesIO(data))
            values = []
            for page in reader.pages:
                text = (page.extract_text() or "").strip()
                if len(text) >= 20:
                    values.append((text.encode("utf-8"), "text/plain", text))
                else:
                    writer = PdfWriter()
                    writer.add_page(page)
                    output = BytesIO()
                    writer.write(output)
                    values.append((output.getvalue(), "application/pdf", None))
            return values
        except Exception as exc:
            raise AppError(
                "lab_pdf_processing_failed", "The PDF pages could not be processed.", 422
            ) from exc


class LabDictionaryService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def resolve(self, name: str) -> tuple[str, str, str | None]:
        normalized = self._normalize(name)
        values = list(
            (
                await self.session.scalars(
                    select(LabTestDictionary).where(LabTestDictionary.active.is_(True))
                )
            ).all()
        )
        for item in values:
            aliases = [item.canonical_name, item.display_name, *item.aliases]
            if normalized in {self._normalize(value) for value in aliases}:
                return item.canonical_name, item.category, item.default_unit
        fallback = "_".join(name.upper().replace("-", " ").split())[:80] or "UNKNOWN"
        return fallback, "other", None

    @staticmethod
    def _normalize(value: str) -> str:
        return "".join(character.lower() for character in value if character.isalnum())


class LabReportService:
    def __init__(
        self,
        session: AsyncSession,
        settings: Settings,
        provider: LabOCRProvider,
        storage: StorageProvider,
    ) -> None:
        self.session = session
        self.settings = settings
        self.provider = provider
        self.storage = storage

    async def create(
        self,
        user_id: UUID,
        *,
        data: bytes,
        filename: str,
        content_type: str,
        report_date: date,
        hospital_name: str | None,
        source_type: str,
        retain_original: bool,
        allow_remote_ocr: bool,
    ) -> LabReportRead:
        if len(data) > self.settings.knowledge_max_upload_bytes:
            raise AppError("lab_report_too_large", "Lab reports must be 30 MB or smaller.", 413)
        LabDocumentProcessor.validate(data, content_type)
        if self.provider.is_remote and not allow_remote_ocr:
            raise AppError(
                "lab_ocr_consent_required",
                "Explicit consent is required before third-party OCR processing.",
                403,
            )
        suffix = Path(filename).suffix or (".pdf" if content_type == "application/pdf" else ".jpg")
        object_key = await self.storage.put_private(
            data, content_type, suffix, prefix=f"lab-reports/{user_id}"
        )
        report = LabReport(
            user_id=user_id,
            report_date=report_date,
            hospital_name=hospital_name,
            source_type=source_type,
            original_file_id=object_key,
            original_filename=Path(filename).name[:500],
            content_type=content_type,
            size_bytes=len(data),
            sha256=sha256(data).hexdigest(),
            ocr_status="processing",
            review_status="draft",
            retain_original=retain_original,
            pages=[],
            results=[],
            ocr_sessions=[],
        )
        self.session.add(report)
        await self.session.flush()
        pages = LabDocumentProcessor.pages(data, content_type)
        ocr = LabOCRSession(
            report_id=report.id,
            provider=self.provider.name,
            model=self.provider.model,
            status="processing",
            remote_processing_authorized=allow_remote_ocr,
            page_count=len(pages),
            items=[],
        )
        report.ocr_sessions.append(ocr)
        dictionary = LabDictionaryService(self.session)
        started = perf_counter()
        try:
            position = 0
            for page_number, (page_bytes, page_type, text_content) in enumerate(pages, start=1):
                report.pages.append(
                    LabReportPage(
                        page_number=page_number,
                        extraction_status="text" if text_content else "ocr",
                        text_content=text_content,
                        page_hash=sha256(page_bytes).hexdigest(),
                    )
                )
                raw_items = await self.provider.analyze_page(page_bytes, page_type, page_number)
                for raw in raw_items:
                    item = await self._ocr_item(dictionary, raw, page_number, position)
                    ocr.items.append(item)
                    position += 1
            ocr.status = "completed"
            ocr.completed_at = datetime.now(UTC)
            report.ocr_status = "completed"
            self.session.add(
                AIUsageLog(
                    user_id=user_id,
                    provider=self.provider.name,
                    model=self.provider.model,
                    task="lab_ocr",
                    image_count=len(pages),
                    latency_ms=int((perf_counter() - started) * 1000),
                    status="success",
                )
            )
            await self.session.commit()
        except Exception as exc:
            ocr.status = "failed"
            ocr.error_summary = str(exc)[:500]
            report.ocr_status = "failed"
            await self.session.commit()
            raise
        return await self.read(user_id, report.id)

    async def _ocr_item(
        self,
        dictionary: LabDictionaryService,
        raw: dict[str, Any],
        page_number: int,
        position: int,
    ) -> LabOCRItem:
        name = str(raw.get("test_name") or "未识别指标")[:200]
        normalized, category, _ = await dictionary.resolve(name)
        value = self._decimal(raw.get("value_numeric"))
        ref_min = self._decimal(raw.get("reference_min"))
        ref_max = self._decimal(raw.get("reference_max"))
        return LabOCRItem(
            page_number=int(raw.get("page_number") or page_number),
            position=int(raw.get("position") or position),
            test_code=str(raw["test_code"])[:80] if raw.get("test_code") else None,
            test_name=name,
            normalized_name=normalized,
            value_numeric=value,
            value_text=str(raw["value_text"])[:240] if raw.get("value_text") else None,
            unit=str(raw["unit"])[:40] if raw.get("unit") else None,
            reference_min=ref_min,
            reference_max=ref_max,
            reference_text=(
                str(raw["reference_text"])[:240] if raw.get("reference_text") else None
            ),
            flag=self._flag(value, ref_min, ref_max),
            category=category,
            confidence=max(
                Decimal("0"),
                min(Decimal("1"), self._decimal(raw.get("confidence")) or Decimal("0")),
            ),
            user_modified=False,
        )

    async def list_all(self, user_id: UUID) -> list[LabReportRead]:
        values = list(
            (
                await self.session.scalars(
                    select(LabReport)
                    .where(LabReport.user_id == user_id, LabReport.deleted_at.is_(None))
                    .options(*REPORT_LOAD)
                    .order_by(LabReport.report_date.desc(), LabReport.created_at.desc())
                )
            )
            .unique()
            .all()
        )
        return [self._read(value) for value in values]

    async def get(self, user_id: UUID, report_id: UUID) -> LabReport:
        report = (
            (
                await self.session.scalars(
                    select(LabReport)
                    .where(
                        LabReport.id == report_id,
                        LabReport.user_id == user_id,
                        LabReport.deleted_at.is_(None),
                    )
                    .options(*REPORT_LOAD)
                )
            )
            .unique()
            .one_or_none()
        )
        if report is None:
            raise AppError("lab_report_not_found", "Lab report was not found.", 404)
        return report

    async def read(self, user_id: UUID, report_id: UUID) -> LabReportRead:
        return self._read(await self.get(user_id, report_id))

    async def patch_item(
        self, user_id: UUID, report_id: UUID, item_id: UUID, payload: LabOCRItemPatch
    ) -> LabReportRead:
        report = await self.get(user_id, report_id)
        item = next(
            (
                value
                for session in report.ocr_sessions
                for value in session.items
                if value.id == item_id
            ),
            None,
        )
        if item is None:
            raise AppError("lab_ocr_item_not_found", "Lab OCR item was not found.", 404)
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(item, field, value)
        if payload.test_name is not None and payload.normalized_name is None:
            normalized, category, _ = await LabDictionaryService(self.session).resolve(
                item.test_name
            )
            item.normalized_name = normalized
            item.category = category
        item.flag = self._flag(item.value_numeric, item.reference_min, item.reference_max)
        item.user_modified = True
        await self.session.commit()
        return await self.read(user_id, report_id)

    async def confirm(
        self, user_id: UUID, report_id: UUID, payload: LabConfirmRequest
    ) -> LabReportRead:
        report = await self.get(user_id, report_id)
        if report.review_status == "confirmed":
            return self._read(report)
        sessions = [value for value in report.ocr_sessions if value.status == "completed"]
        if not sessions:
            raise AppError("lab_ocr_not_ready", "Lab OCR draft is not ready for review.", 409)
        selected = set(payload.item_ids or [])
        items = sessions[-1].items
        for item in items:
            if selected and item.id not in selected:
                continue
            report.results.append(
                LabResult(
                    test_code=item.test_code,
                    test_name=item.test_name,
                    normalized_name=item.normalized_name,
                    value_numeric=item.value_numeric,
                    value_text=item.value_text,
                    unit=item.unit,
                    reference_min=item.reference_min,
                    reference_max=item.reference_max,
                    reference_text=item.reference_text,
                    flag=item.flag,
                    category=item.category,
                    confidence=item.confidence,
                    user_confirmed=True,
                )
            )
        if not report.results:
            raise AppError("lab_no_items_selected", "Select at least one lab result.", 422)
        report.review_status = "confirmed"
        if not report.retain_original and report.original_file_id:
            await self.storage.delete(report.original_file_id)
            report.original_file_id = None
        await self.session.commit()
        return await self.read(user_id, report_id)

    async def delete(self, user_id: UUID, report_id: UUID) -> None:
        report = await self.get(user_id, report_id)
        if report.original_file_id:
            await self.storage.delete(report.original_file_id)
            report.original_file_id = None
        now = datetime.now(UTC)
        report.deleted_at = now
        report.review_status = "deleted"
        for result in report.results:
            result.deleted_at = now
        await self.session.commit()

    async def delete_result(self, user_id: UUID, result_id: UUID) -> None:
        value = await self.session.scalar(
            select(LabResult)
            .join(LabReport, LabReport.id == LabResult.report_id)
            .where(
                LabResult.id == result_id,
                LabResult.deleted_at.is_(None),
                LabReport.user_id == user_id,
                LabReport.deleted_at.is_(None),
            )
        )
        if value is None:
            raise AppError("lab_result_not_found", "Lab result was not found.", 404)
        value.deleted_at = datetime.now(UTC)
        await self.session.commit()

    @staticmethod
    def _read(report: LabReport) -> LabReportRead:
        sessions = sorted(report.ocr_sessions, key=lambda value: value.created_at)
        draft = sessions[-1].items if sessions else []
        return LabReportRead(
            id=report.id,
            report_date=report.report_date,
            hospital_name=report.hospital_name,
            source_type=report.source_type,
            original_filename=report.original_filename,
            ocr_status=report.ocr_status,
            review_status=report.review_status,
            retain_original=report.retain_original,
            draft_items=[LabOCRItemRead.model_validate(item) for item in draft],
            results=[
                LabResultRead.model_validate(item)
                for item in report.results
                if item.deleted_at is None
            ],
            created_at=report.created_at,
            updated_at=report.updated_at,
        )

    @staticmethod
    def _decimal(value: object) -> Decimal | None:
        if value is None or value == "":
            return None
        try:
            return Decimal(str(value))
        except Exception:
            return None

    @staticmethod
    def _flag(value: Decimal | None, minimum: Decimal | None, maximum: Decimal | None) -> str:
        if value is None:
            return "unknown"
        if minimum is not None and value < minimum:
            return "low"
        if maximum is not None and value > maximum:
            return "high"
        if minimum is not None or maximum is not None:
            return "normal"
        return "unknown"


class LabTrendService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def build(self, user_id: UUID, normalized_name: str) -> LabTrendRead:
        dictionary = await self.session.scalar(
            select(LabTestDictionary).where(
                LabTestDictionary.canonical_name == normalized_name.upper(),
                LabTestDictionary.active.is_(True),
            )
        )
        rows = (
            await self.session.execute(
                select(LabResult, LabReport)
                .join(LabReport, LabReport.id == LabResult.report_id)
                .where(
                    LabReport.user_id == user_id,
                    LabReport.deleted_at.is_(None),
                    LabReport.review_status == "confirmed",
                    LabResult.normalized_name == normalized_name.upper(),
                    LabResult.user_confirmed.is_(True),
                    LabResult.deleted_at.is_(None),
                    LabResult.value_numeric.is_not(None),
                )
                .order_by(LabReport.report_date)
            )
        ).all()
        if not rows:
            raise AppError("lab_trend_not_found", "No confirmed trend data was found.", 404)
        canonical_unit = (
            dictionary.default_unit if dictionary and dictionary.default_unit else rows[0][0].unit
        )
        if canonical_unit is None:
            raise AppError("lab_trend_unit_missing", "Lab trend has no comparable unit.", 422)
        points: list[LabTrendPoint] = []
        for result, report in rows:
            assert result.value_numeric is not None
            value = result.value_numeric
            minimum = result.reference_min
            maximum = result.reference_max
            if result.unit and result.unit != canonical_unit:
                value = LabUnitConversionService.convert(
                    result.normalized_name, value, result.unit, canonical_unit
                )
                if minimum is not None:
                    minimum = LabUnitConversionService.convert(
                        result.normalized_name, minimum, result.unit, canonical_unit
                    )
                if maximum is not None:
                    maximum = LabUnitConversionService.convert(
                        result.normalized_name, maximum, result.unit, canonical_unit
                    )
            points.append(
                LabTrendPoint(
                    report_id=report.id,
                    report_date=report.report_date,
                    value=value,
                    unit=canonical_unit,
                    flag=result.flag,
                    reference_min=minimum,
                    reference_max=maximum,
                )
            )
        return LabTrendRead(
            normalized_name=normalized_name.upper(),
            display_name=dictionary.display_name if dictionary else rows[0][0].test_name,
            canonical_unit=canonical_unit,
            points=points,
        )
