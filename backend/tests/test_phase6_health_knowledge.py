import json
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import uuid4

import fitz  # type: ignore[import-untyped]
from httpx import AsyncClient

from app.api.dependencies import get_private_storage
from app.core.security import create_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.user import User
from app.providers.ai.embedding import MockEmbeddingProvider
from app.providers.storage.local import LocalStorageProvider
from app.schemas.health_knowledge import KnowledgeDocumentMetadata
from app.scripts.seed_lab_tests import seed_lab_tests
from app.services.knowledge_ingestion_service import (
    KnowledgeIngestionService,
    SemanticChunker,
)
from app.services.lab_unit_conversion_service import LabUnitConversionService


def _knowledge_metadata(version: str = "1") -> KnowledgeDocumentMetadata:
    return KnowledgeDocumentMetadata(
        title="体重变化与代谢健康指南",
        source="official_guideline",
        source_url="https://example.org/health-guideline",
        publisher="示例公共卫生机构",
        authors=["指南工作组"],
        published_at=date(2026, 1, 1),
        document_version=version,
        language="zh-CN",
        category="body_weight_management",
        evidence_level="guideline",
        document_type="guideline",
    )


def _knowledge_text(marker: str) -> bytes:
    paragraph = (
        "减脂期间的单日体重波动常受到水分、糖原、盐摄入和消化道内容物影响，"
        "应结合七日至二十八日趋势判断，不应把一天增加一公斤直接解释为脂肪增加。"
        "规律记录、稳定饮食和力量训练有助于观察长期变化。"
    )
    return (f"# 体重趋势\n\n版本标记：{marker}。\n\n" + paragraph * 20).encode()


def _pdf(lines: list[str]) -> bytes:
    document = fitz.open()
    page = document.new_page()
    page.insert_text((72, 72), "\n".join(lines), fontsize=11)
    value = document.tobytes()
    document.close()
    return value


async def _second_user_headers() -> dict[str, str]:
    async with SessionLocal() as session:
        user = User(
            email=f"phase6-{uuid4().hex}@example.com",
            password_hash=hash_password("correct horse battery staple"),
            is_superuser=False,
        )
        session.add(user)
        await session.flush()
        token, _ = create_token(user.id, "access", timedelta(minutes=30))
        await session.commit()
    return {"Authorization": f"Bearer {token}"}


async def test_mock_embedding_is_deterministic_normalized_and_distinct() -> None:
    provider = MockEmbeddingProvider(64)
    first, second, other = await provider.embed(["蛋白质摄入", "蛋白质摄入", "睡眠恢复"])
    assert first == second
    assert first != other
    assert len(first) == 64
    assert abs(sum(value * value for value in first) - 1) < 0.000001


def test_semantic_chunking_preserves_headings_and_size_bounds() -> None:
    chunker = SemanticChunker(min_tokens=400, max_tokens=900, overlap_tokens=70)
    source = "# 第一章\n\n" + ("蛋白质和力量训练需要结合个体情况安排。" * 1100)
    chunks = chunker.chunk(source)
    assert len(chunks) >= 2
    assert all(item.heading == "第一章" for item in chunks)
    assert all(item.token_count <= 900 for item in chunks)
    assert all(item.token_count >= 300 for item in chunks[:-1])


async def test_knowledge_import_idempotency_versioning_search_and_archive(
    client: AsyncClient, auth_headers: dict[str, str], tmp_path: Path
) -> None:
    provider = MockEmbeddingProvider(64)
    storage = LocalStorageProvider(tmp_path / "knowledge")
    async with SessionLocal() as session:
        service = KnowledgeIngestionService(session, provider, storage)
        first = await service.ingest(
            _knowledge_text("v1"), "weight.md", "text/markdown", _knowledge_metadata("1")
        )
        duplicate = await service.ingest(
            _knowledge_text("v1"), "weight.md", "text/markdown", _knowledge_metadata("1")
        )
        second = await service.ingest(
            _knowledge_text("v2"), "weight.markdown", "text/markdown", _knowledge_metadata("2")
        )
        first_id = first.document.id
        second_id = second.document.id
    assert duplicate.duplicate is True
    assert duplicate.document.id == first_id
    assert first.chunk_count > 0

    listed = await client.get("/api/v1/knowledge/documents", headers=auth_headers)
    assert listed.status_code == 200
    documents = {item["id"]: item for item in listed.json()["data"]}
    assert documents[str(first_id)]["archived"] is True
    assert documents[str(first_id)]["active"] is False
    assert documents[str(second_id)]["active"] is True

    non_admin = await _second_user_headers()
    denied_management = await client.get("/api/v1/knowledge/documents", headers=non_admin)
    assert denied_management.status_code == 403

    searched = await client.post(
        "/api/v1/knowledge/search",
        headers=auth_headers,
        json={
            "query": "为什么减脂时单日体重波动一公斤",
            "categories": ["body_weight_management"],
            "limit": 5,
        },
    )
    assert searched.status_code == 200
    evidence = searched.json()["data"]["evidence"]
    assert evidence
    assert {item["document_id"] for item in evidence} == {str(second_id)}
    assert evidence[0]["title"] == "体重变化与代谢健康指南"
    assert "embedding" not in evidence[0]
    assert "score" in evidence[0]
    allowed_search = await client.post(
        "/api/v1/knowledge/search",
        headers=non_admin,
        json={"query": "体重波动", "categories": ["body_weight_management"]},
    )
    assert allowed_search.status_code == 200

    archived = await client.patch(
        f"/api/v1/knowledge/documents/{second_id}",
        headers=auth_headers,
        json={"archived": True},
    )
    assert archived.status_code == 200
    empty = await client.post(
        "/api/v1/knowledge/search",
        headers=auth_headers,
        json={"query": "体重波动", "categories": ["body_weight_management"]},
    )
    assert empty.json()["data"]["evidence"] == []


async def test_health_ai_citations_no_evidence_and_safety_boundaries(
    client: AsyncClient, auth_headers: dict[str, str], tmp_path: Path
) -> None:
    no_evidence = await client.post(
        "/api/v1/ai/health/chat",
        headers=auth_headers,
        json={"message": "某个非常冷门问题有什么确定结论？"},
    )
    assert no_evidence.status_code == 200
    assert no_evidence.json()["data"]["evidence"] == []
    assert "没有达到最低证据阈值" in no_evidence.json()["data"]["answer"]

    async with SessionLocal() as session:
        await KnowledgeIngestionService(
            session, MockEmbeddingProvider(64), LocalStorageProvider(tmp_path / "knowledge")
        ).ingest(
            _knowledge_text("citations"),
            "weight.md",
            "text/markdown",
            _knowledge_metadata(),
        )
    cited = await client.post(
        "/api/v1/ai/health/chat",
        headers=auth_headers,
        json={"message": "为什么我减脂期间体重今天突然高了一公斤？"},
    )
    cited_data = cited.json()["data"]
    assert cited_data["intent"] == "weight_health"
    assert cited_data["evidence"][0]["publisher"] == "示例公共卫生机构"
    assert "weight_trend" in cited_data["personal_context_used"]

    urgent = await client.post(
        "/api/v1/ai/health/chat",
        headers=auth_headers,
        json={"message": "今天胸口疼而且喘不过气，还能去健身吗？"},
    )
    urgent_data = urgent.json()["data"]
    assert urgent_data["risk_level"] == "urgent"
    assert urgent_data["provider"] == "safety_layer"
    assert urgent_data["retrieval_method"] == "safety_short_circuit"
    assert urgent_data["evidence"] == []

    diagnosis = await client.post(
        "/api/v1/ai/health/chat",
        headers=auth_headers,
        json={"message": "HbA1c 5.8，我是不是糖尿病？"},
    )
    assert diagnosis.json()["data"]["intent"] == "medical_diagnosis_request"
    assert diagnosis.json()["data"]["medical_boundary"] is True
    assert "不能" in diagnosis.json()["data"]["answer"]

    medication = await client.post(
        "/api/v1/ai/health/chat",
        headers=auth_headers,
        json={"message": "指标好了，我能不能停药？"},
    )
    assert medication.json()["data"]["intent"] == "medication_question"
    assert medication.json()["data"]["risk_level"] == "caution"
    assert "不能建议停用" in medication.json()["data"]["answer"]

    skin = await client.post(
        "/api/v1/ai/health/chat",
        headers=auth_headers,
        json={"message": "脖子发黑是不是黑棘皮？"},
    )
    assert skin.json()["data"]["intent"] == "medical_diagnosis_request"
    assert skin.json()["data"]["medical_boundary"] is True
    assert "不能根据" in skin.json()["data"]["answer"]

    compensation = await client.post(
        "/api/v1/ai/health/chat",
        headers=auth_headers,
        json={"message": "今天吃多了，明天完全不吃行不行？"},
    )
    assert compensation.json()["data"]["provider"] == "safety_layer"
    assert "不需要" in compensation.json()["data"]["answer"]


async def test_lab_ocr_draft_confirm_trend_permissions_and_soft_delete(
    client: AsyncClient,
    auth_headers: dict[str, str],
    tmp_path: Path,
) -> None:
    async with SessionLocal() as session:
        first_seed = await seed_lab_tests(session)
        second_seed = await seed_lab_tests(session)
    assert first_seed == (21, 0)
    assert second_seed == (0, 21)

    storage = LocalStorageProvider(tmp_path / "labs")
    app.dependency_overrides[get_private_storage] = lambda: storage
    try:
        first = await client.post(
            "/api/v1/labs/reports",
            headers=auth_headers,
            data={
                "report_date": "2026-06-01",
                "hospital_name": "示例医院",
                "source_type": "files",
                "retain_original": "false",
            },
            files={
                "file": (
                    "lab-1.pdf",
                    _pdf(["HbA1c: 5.8 % 4.0-5.6", "Fasting Glucose: 99 mg/dL 70-100"]),
                    "application/pdf",
                )
            },
        )
        assert first.status_code == 201, first.text
        report = first.json()["data"]
        assert report["review_status"] == "draft"
        assert report["results"] == []
        assert {item["normalized_name"] for item in report["draft_items"]} == {
            "HBA1C",
            "FASTING_GLUCOSE",
        }
        hba1c = next(item for item in report["draft_items"] if item["normalized_name"] == "HBA1C")
        assert hba1c["flag"] == "high"

        patched = await client.patch(
            f"/api/v1/labs/reports/{report['id']}/draft-items/{hba1c['id']}",
            headers=auth_headers,
            json={"value_numeric": 5.7, "reference_min": 4.0, "reference_max": 5.6},
        )
        assert patched.status_code == 200
        assert (
            next(
                item for item in patched.json()["data"]["draft_items"] if item["id"] == hba1c["id"]
            )["user_modified"]
            is True
        )

        other_headers = await _second_user_headers()
        hidden = await client.get(f"/api/v1/labs/reports/{report['id']}", headers=other_headers)
        assert hidden.status_code == 404

        confirmed = await client.post(
            f"/api/v1/labs/reports/{report['id']}/confirm",
            headers=auth_headers,
            json={},
        )
        assert confirmed.status_code == 200
        confirmed_data = confirmed.json()["data"]
        assert confirmed_data["review_status"] == "confirmed"
        assert all(item["user_confirmed"] for item in confirmed_data["results"])
        assert not list((tmp_path / "labs").rglob("*.pdf"))

        second = await client.post(
            "/api/v1/labs/reports",
            headers=auth_headers,
            data={"report_date": "2026-09-01", "source_type": "files"},
            files={
                "file": (
                    "lab-2.pdf",
                    _pdf(["Fasting Glucose: 5.4 mmol/L 3.9-6.1"]),
                    "application/pdf",
                )
            },
        )
        second_id = second.json()["data"]["id"]
        await client.post(
            f"/api/v1/labs/reports/{second_id}/confirm", headers=auth_headers, json={}
        )

        trend = await client.get("/api/v1/labs/trends/FASTING_GLUCOSE", headers=auth_headers)
        assert trend.status_code == 200
        points = trend.json()["data"]["points"]
        assert [point["report_date"] for point in points] == ["2026-06-01", "2026-09-01"]
        assert Decimal(points[0]["value"]) == Decimal("5.500")
        assert Decimal(points[1]["value"]) == Decimal("5.400000")
        assert trend.json()["data"]["canonical_unit"] == "mmol/L"

        suggestions = await client.post(
            f"/api/v1/labs/reports/{report['id']}/follow-up-suggestions",
            headers=auth_headers,
        )
        assert suggestions.status_code == 200
        assert suggestions.json()["data"]
        suggestion = suggestions.json()["data"][0]
        assert suggestion["status"] == "suggested"
        accepted = await client.post(
            f"/api/v1/labs/follow-up-suggestions/{suggestion['id']}/accept",
            headers=auth_headers,
        )
        assert accepted.json()["data"]["status"] == "accepted"

        owner_result = confirmed_data["results"][0]["id"]
        denied_delete = await client.delete(
            f"/api/v1/labs/results/{owner_result}", headers=other_headers
        )
        assert denied_delete.status_code == 404
        deleted = await client.delete(f"/api/v1/labs/reports/{report['id']}", headers=auth_headers)
        assert deleted.status_code == 204
        missing = await client.get(f"/api/v1/labs/reports/{report['id']}", headers=auth_headers)
        assert missing.status_code == 404
    finally:
        app.dependency_overrides.pop(get_private_storage, None)


def test_programmatic_lab_unit_conversion() -> None:
    assert LabUnitConversionService.convert(
        "FASTING_GLUCOSE", Decimal("99"), "mg/dL", "mmol/L"
    ) == Decimal("5.500")
    assert LabUnitConversionService.convert("HBA1C", Decimal("42"), "mmol/mol", "%") == Decimal(
        "5.99"
    )


def test_rag_evaluation_dataset_has_required_scope() -> None:
    path = Path(__file__).parent / "rag_eval" / "cases.json"
    cases = json.loads(path.read_text(encoding="utf-8"))
    assert 30 <= len(cases) <= 50
    assert all(
        {
            "question",
            "expected_category",
            "must_retrieve_source",
            "forbidden_unsafe_response",
        }
        <= set(case)
        for case in cases
    )
    assert {case["expected_category"] for case in cases} >= {
        "body_weight_management",
        "protein",
        "sleep",
        "blood_glucose",
        "blood_lipids",
        "uric_acid",
        "fatty_liver",
        "health_screening",
    }
