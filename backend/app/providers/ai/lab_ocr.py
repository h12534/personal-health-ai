import base64
import json
import re
from decimal import Decimal
from typing import Any

import httpx

from app.core.errors import AppError


class MockLabOCRProvider:
    name = "mock"
    model = "mock-lab-ocr-v1"
    is_remote = False

    _line = re.compile(
        r"^(?P<name>.{2,80}?)[:：]\s*(?P<value>-?\d+(?:\.\d+)?)\s*"
        r"(?P<unit>%|mmol/L|mg/dL|U/L|μmol/L|umol/L|g/L|10\^9/L)?\s*"
        r"(?P<low>-?\d+(?:\.\d+)?)?\s*[-–~至]\s*(?P<high>-?\d+(?:\.\d+)?)?$",
        re.IGNORECASE,
    )

    async def analyze_page(
        self, page_bytes: bytes, content_type: str, page_number: int
    ) -> list[dict[str, Any]]:
        if content_type != "text/plain":
            return []
        text = page_bytes.decode("utf-8", errors="ignore")
        values: list[dict[str, Any]] = []
        for position, raw in enumerate(text.splitlines()):
            match = self._line.match(raw.strip())
            if match is None:
                continue
            values.append(
                {
                    "page_number": page_number,
                    "position": position,
                    "test_name": match.group("name").strip(),
                    "value_numeric": str(Decimal(match.group("value"))),
                    "unit": match.group("unit"),
                    "reference_min": match.group("low"),
                    "reference_max": match.group("high"),
                    "confidence": "0.95",
                }
            )
        return values


class OpenAICompatibleLabOCRProvider:
    name = "openai_compatible"
    is_remote = True

    def __init__(self, *, base_url: str, api_key: str, model: str, timeout_seconds: int) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        self.timeout_seconds = timeout_seconds

    async def analyze_page(
        self, page_bytes: bytes, content_type: str, page_number: int
    ) -> list[dict[str, Any]]:
        schema_hint = (
            'Return JSON only as {"items":[{"test_name":str,"test_code":str|null,'
            '"value_numeric":number|null,"value_text":str|null,"unit":str|null,'
            '"reference_min":number|null,"reference_max":number|null,'
            '"reference_text":str|null,"confidence":number}]}。'
            "只提取页面明确出现的化验指标，不诊断，不补全缺失值。"
        )
        if content_type == "text/plain":
            page_content: str | list[dict[str, object]] = (
                f"体检报告第 {page_number} 页文本：\n"
                + page_bytes.decode("utf-8", errors="replace")
            )
        else:
            encoded = base64.b64encode(page_bytes).decode("ascii")
            page_content = [
                {"type": "text", "text": f"体检报告第 {page_number} 页"},
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:{content_type};base64,{encoded}"},
                },
            ]
        body: dict[str, Any] = {
            "model": self.model,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": schema_hint},
                {"role": "user", "content": page_content},
            ],
        }
        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                response = await client.post(
                    f"{self.base_url}/chat/completions",
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    json=body,
                )
                response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            payload = json.loads(content)
        except (httpx.HTTPError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise AppError("lab_ocr_provider_error", "Lab OCR provider failed.", 502) from exc
        items = payload.get("items", [])
        if not isinstance(items, list):
            raise AppError("lab_ocr_schema_invalid", "Lab OCR returned invalid data.", 502)
        return [
            dict(item, page_number=page_number, position=index) for index, item in enumerate(items)
        ]
