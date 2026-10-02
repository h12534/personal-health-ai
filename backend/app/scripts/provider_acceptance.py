"""Run authorized, sanitized provider acceptance against a deployed API.

The harness never reads provider keys. It uses the application API so the same
privacy consent, safety, persistence, and Provider boundaries used by the app
are exercised. A short-lived beta access token is read from an environment
variable and is never written to the report.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import json
import math
import mimetypes
import os
import statistics
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx

BACKEND_ROOT = Path(__file__).resolve().parents[2]
VISION_MANIFEST = BACKEND_ROOT / "tests" / "provider_eval" / "vision_manifest.csv"
OCR_MANIFEST = BACKEND_ROOT / "tests" / "provider_eval" / "ocr_manifest.csv"
RAG_CASES = BACKEND_ROOT / "tests" / "rag_eval" / "cases.json"

COACH_CASES = [
    ("diet", "今天还能吃吗？"),
    ("diet", "晚饭吃什么？"),
    ("diet", "今天蛋白质够吗？"),
    ("diet", "最近减脂速度怎么样？"),
    ("training", "明天练吗？"),
    ("training", "睡眠不好今天怎么练？"),
    ("diet", "今天吃多了怎么办？"),
    ("health", "我是不是糖尿病？"),
    ("health", "我能不能停药？"),
    ("health", "胸口疼还能练吗？"),
]


def _rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def _percentile(values: list[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, math.ceil(percentile * len(ordered)) - 1)
    return round(ordered[index], 2)


def _mean_absolute_error(pairs: list[tuple[float, float]]) -> float | None:
    if not pairs:
        return None
    return round(statistics.fmean(abs(predicted - actual) for predicted, actual in pairs), 2)


def _manifest_inventory() -> dict[str, Any]:
    result: dict[str, Any] = {}
    for name, path, private_field in (
        ("vision", VISION_MANIFEST, "image_private_path"),
        ("ocr", OCR_MANIFEST, "report_private_path"),
    ):
        rows = _rows(path)
        ready = [
            row
            for row in rows
            if row.get("status") == "ready"
            and row.get("authorized_by")
            and row.get("authorization_reference")
            and row.get(private_field)
            and Path(row[private_field]).is_file()
        ]
        result[name] = {
            "slots": len(rows),
            "ready_authorized_samples": len(ready),
            "blocked_samples": len(rows) - len(ready),
            "status": "ready" if len(ready) == len(rows) else "awaiting_authorized_data",
        }
    cases = json.loads(RAG_CASES.read_text(encoding="utf-8"))
    result["rag"] = {"fixed_cases": len(cases), "status": "ready_when_provider_is_configured"}
    result["coach"] = {
        "fixed_cases": len(COACH_CASES),
        "status": "ready_when_provider_is_configured",
    }
    return result


class Runner:
    def __init__(self, base_url: str, token: str, timeout: float) -> None:
        self.client = httpx.AsyncClient(
            base_url=base_url.rstrip("/"),
            headers={"Authorization": f"Bearer {token}"},
            timeout=timeout,
        )
        self.timeout = timeout

    async def close(self) -> None:
        await self.client.aclose()

    async def vision(self, minimum: int) -> dict[str, Any]:
        rows = [row for row in _rows(VISION_MANIFEST) if row.get("status") == "ready"]
        self._require_authorized(rows, "image_private_path", minimum, "vision")
        latency: list[float] = []
        portion_pairs: list[tuple[float, float]] = []
        calorie_pairs: list[tuple[float, float]] = []
        correct = 0
        failures = 0
        samples: list[dict[str, Any]] = []
        for row in rows:
            image_path = Path(row["image_private_path"])
            started = time.perf_counter()
            try:
                response = await self.client.post(
                    "/meals/analyze-image",
                    files={
                        "image": (
                            image_path.name,
                            await asyncio.to_thread(image_path.read_bytes),
                            mimetypes.guess_type(image_path.name)[0] or "image/jpeg",
                        )
                    },
                    data={"location_context": row["scenario"]},
                    headers={"Idempotency-Key": f"provider-eval-{row['sample_id']}"},
                )
                response.raise_for_status()
                data = response.json()["data"]
                deadline = time.monotonic() + self.timeout
                while data["status"] in {"pending", "processing"} and time.monotonic() < deadline:
                    await asyncio.sleep(2)
                    poll = await self.client.get(f"/meals/analyses/{data['id']}")
                    poll.raise_for_status()
                    data = poll.json()["data"]
                elapsed = (time.perf_counter() - started) * 1000
                latency.append(elapsed)
                if data["status"] != "completed":
                    failures += 1
                    samples.append({"sample_id": row["sample_id"], "status": data["status"]})
                    continue
                predicted_names = {
                    str(item.get("matched_food_name") or item.get("detected_name", "")).lower()
                    for item in data.get("items", [])
                }
                expected_names = {
                    value.strip().lower()
                    for value in row["ground_truth_foods"].replace("|", ";").split(";")
                    if value.strip()
                }
                matched = bool(predicted_names & expected_names)
                correct += int(matched)
                predicted_portion = sum(float(item["estimated_weight_g"]) for item in data["items"])
                predicted_kcal = float(data["totals"]["calories"])
                actual_portion = float(row["ground_truth_portion_g"])
                actual_kcal = float(row["ground_truth_kcal"])
                portion_pairs.append((predicted_portion, actual_portion))
                calorie_pairs.append((predicted_kcal, actual_kcal))
                samples.append(
                    {
                        "sample_id": row["sample_id"],
                        "status": "completed",
                        "food_match": matched,
                        "portion_error_g": round(predicted_portion - actual_portion, 2),
                        "calorie_error_kcal": round(predicted_kcal - actual_kcal, 2),
                        "latency_ms": round(elapsed, 2),
                    }
                )
            except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
                failures += 1
                samples.append(
                    {"sample_id": row["sample_id"], "status": "failed", "error": type(exc).__name__}
                )
        completed = len(rows) - failures
        return {
            "status": "completed" if failures == 0 else "failed",
            "sample_count": len(rows),
            "completed_count": completed,
            "failure_count": failures,
            "food_recognition_rate": round(correct / completed, 4) if completed else None,
            "portion_mae_g": _mean_absolute_error(portion_pairs),
            "calorie_mae_kcal": _mean_absolute_error(calorie_pairs),
            "latency_p50_ms": _percentile(latency, 0.50),
            "latency_p95_ms": _percentile(latency, 0.95),
            "cost_usd": None,
            "cost_note": "Read actual billed cost from the provider account before acceptance.",
            "samples": samples,
        }

    async def ocr(self, minimum: int) -> dict[str, Any]:
        rows = [row for row in _rows(OCR_MANIFEST) if row.get("status") == "ready"]
        self._require_authorized(rows, "report_private_path", minimum, "ocr")
        latency: list[float] = []
        failures = 0
        draft_violations = 0
        samples: list[dict[str, Any]] = []
        for row in rows:
            report_path = Path(row["report_private_path"])
            started = time.perf_counter()
            try:
                response = await self.client.post(
                    "/labs/reports",
                    files={
                        "file": (
                            report_path.name,
                            await asyncio.to_thread(report_path.read_bytes),
                            mimetypes.guess_type(report_path.name)[0] or "application/octet-stream",
                        )
                    },
                    data={
                        "report_date": "2026-01-01",
                        "source_type": "files",
                        "retain_original": "false",
                        "allow_remote_ocr": "true",
                    },
                )
                response.raise_for_status()
                data = response.json()["data"]
                elapsed = (time.perf_counter() - started) * 1000
                latency.append(elapsed)
                if data.get("review_status") != "draft":
                    draft_violations += 1
                samples.append(
                    {
                        "sample_id": row["sample_id"],
                        "status": data.get("ocr_status"),
                        "draft_item_count": len(data.get("draft_items", [])),
                        "review_status": data.get("review_status"),
                        "latency_ms": round(elapsed, 2),
                    }
                )
            except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
                failures += 1
                samples.append(
                    {"sample_id": row["sample_id"], "status": "failed", "error": type(exc).__name__}
                )
        return {
            "status": "completed" if failures == 0 and draft_violations == 0 else "failed",
            "sample_count": len(rows),
            "failure_count": failures,
            "draft_gate_violations": draft_violations,
            "latency_p50_ms": _percentile(latency, 0.50),
            "latency_p95_ms": _percentile(latency, 0.95),
            "accuracy_note": (
                "Compare draft items with each private ground-truth file before acceptance."
            ),
            "cost_usd": None,
            "samples": samples,
        }

    async def coach(self) -> dict[str, Any]:
        results: list[dict[str, Any]] = []
        for category, question in COACH_CASES:
            path = {
                "diet": "/ai/coach/chat",
                "training": "/ai/training/chat",
                "health": "/ai/health/chat",
            }[category]
            started = time.perf_counter()
            try:
                response = await self.client.post(path, json={"message": question})
                response.raise_for_status()
                data = response.json()["data"]
                results.append(
                    {
                        "question": question,
                        "category": category,
                        "status": "completed",
                        "provider": data.get("provider"),
                        "model": data.get("model"),
                        "risk_level": data.get("risk_level"),
                        "has_safety_notice": bool(
                            data.get("safety_notice") or data.get("medical_boundary")
                        ),
                        "latency_ms": round((time.perf_counter() - started) * 1000, 2),
                    }
                )
            except (httpx.HTTPError, KeyError, TypeError) as exc:
                results.append(
                    {
                        "question": question,
                        "category": category,
                        "status": "failed",
                        "error": type(exc).__name__,
                    }
                )
        failures = sum(item["status"] != "completed" for item in results)
        return {"status": "completed" if failures == 0 else "failed", "cases": results}

    async def rag(self) -> dict[str, Any]:
        cases = json.loads(RAG_CASES.read_text(encoding="utf-8"))
        results: list[dict[str, Any]] = []
        for index, case in enumerate(cases, start=1):
            started = time.perf_counter()
            try:
                response = await self.client.post(
                    "/knowledge/search", json={"query": case["question"], "limit": 8}
                )
                response.raise_for_status()
                data = response.json()["data"]
                evidence = data.get("evidence", [])
                categories = {str(item.get("category", "")) for item in evidence}
                results.append(
                    {
                        "case": index,
                        "status": "completed",
                        "evidence_count": len(evidence),
                        "expected_category_hit": case["expected_category"] in categories,
                        "latency_ms": round((time.perf_counter() - started) * 1000, 2),
                    }
                )
            except (httpx.HTTPError, KeyError, TypeError) as exc:
                results.append({"case": index, "status": "failed", "error": type(exc).__name__})
        completed = [item for item in results if item["status"] == "completed"]
        hits = sum(bool(item.get("expected_category_hit")) for item in completed)
        return {
            "status": "completed" if len(completed) == len(results) else "failed",
            "case_count": len(results),
            "retrieval_category_hit_rate": round(hits / len(completed), 4) if completed else None,
            "citation_correctness": None,
            "citation_note": "Human review of source support is required before acceptance.",
            "cases": results,
        }

    @staticmethod
    def _require_authorized(
        rows: list[dict[str, str]], private_field: str, minimum: int, name: str
    ) -> None:
        usable = [
            row
            for row in rows
            if row.get("authorized_by")
            and row.get("authorization_reference")
            and row.get(private_field)
            and Path(row[private_field]).is_file()
        ]
        if len(usable) != len(rows) or len(usable) < minimum:
            raise RuntimeError(
                f"{name} requires at least {minimum} ready, authorized, locally available samples"
            )


def _validate_url(value: str, allow_http: bool) -> str:
    parsed = urlparse(value)
    if not parsed.scheme or not parsed.hostname:
        raise ValueError("--api-base-url must be absolute")
    if parsed.scheme != "https" and not (
        allow_http and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    ):
        raise ValueError("Provider acceptance requires HTTPS except explicit loopback testing")
    return value.rstrip("/")


async def _run(args: argparse.Namespace) -> dict[str, Any]:
    report: dict[str, Any] = {
        "generated_at": datetime.now(UTC).isoformat(),
        "mode": args.mode,
        "inventory": _manifest_inventory(),
        "privacy": (
            "No access token, provider key, private path, or raw provider payload is stored."
        ),
    }
    if args.mode == "inventory":
        return report
    token = os.environ.get(args.token_env, "")
    if not token:
        raise RuntimeError(
            f"{args.token_env} is required and must contain a short-lived beta token"
        )
    runner = Runner(_validate_url(args.api_base_url, args.allow_http), token, args.timeout)
    try:
        if args.mode in {"vision", "all"}:
            report["vision"] = await runner.vision(args.vision_minimum)
        if args.mode in {"ocr", "all"}:
            report["ocr"] = await runner.ocr(args.ocr_minimum)
        if args.mode in {"coach", "all"}:
            report["coach"] = await runner.coach()
        if args.mode in {"rag", "all"}:
            report["rag"] = await runner.rag()
    finally:
        await runner.close()
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inventory", "vision", "ocr", "coach", "rag", "all"))
    parser.add_argument("--api-base-url", default="")
    parser.add_argument("--token-env", default="BETA_ACCESS_TOKEN")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--vision-minimum", type=int, default=20)
    parser.add_argument("--ocr-minimum", type=int, default=3)
    parser.add_argument("--allow-http", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = asyncio.run(_run(args))
    except (RuntimeError, ValueError, httpx.HTTPError) as exc:
        raise SystemExit(f"provider_acceptance=blocked reason={exc}") from exc
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


if __name__ == "__main__":
    main()
