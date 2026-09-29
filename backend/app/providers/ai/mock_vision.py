from copy import deepcopy
from typing import Any

from app.providers.ai.base import VisionProviderResponse

DEFAULT_RESULT: dict[str, Any] = {
    "no_food_detected": False,
    "foods": [
        {
            "detected_name": "米饭",
            "aliases": ["白米饭"],
            "estimated_weight_g": 180,
            "weight_range": {"min_g": 140, "max_g": 230},
            "portion_description": "约一碗",
            "cooking_method": "蒸",
            "recognition_confidence": 0.96,
            "portion_confidence": 0.72,
            "visible_components": ["白米饭"],
            "possible_hidden_ingredients": [],
            "possible_oil_weight": None,
        },
        {
            "detected_name": "鸡胸肉",
            "aliases": ["鸡肉"],
            "estimated_weight_g": 120,
            "weight_range": {"min_g": 90, "max_g": 160},
            "portion_description": "约一掌心",
            "cooking_method": "煎",
            "recognition_confidence": 0.88,
            "portion_confidence": 0.66,
            "visible_components": ["鸡肉块"],
            "possible_hidden_ingredients": ["盐", "酱油"],
            "possible_oil_weight": {"min_g": 3, "max_g": 10},
        },
        {
            "detected_name": "西兰花",
            "aliases": ["花椰菜"],
            "estimated_weight_g": 100,
            "weight_range": {"min_g": 70, "max_g": 140},
            "portion_description": "约半碗",
            "cooking_method": "清炒",
            "recognition_confidence": 0.91,
            "portion_confidence": 0.7,
            "visible_components": ["西兰花"],
            "possible_hidden_ingredients": ["盐"],
            "possible_oil_weight": {"min_g": 2, "max_g": 8},
        },
    ],
    "overall_confidence": 0.82,
    "warnings": ["份量基于单张照片估算，请在保存前确认。"],
}


class MockVisionProvider:
    name = "mock"
    model = "mock-meal-v1"
    is_remote = False

    def __init__(
        self, payload: dict[str, Any] | None = None, error: Exception | None = None
    ) -> None:
        self.payload = payload or DEFAULT_RESULT
        self.error = error

    async def analyze_meal(
        self, image_bytes: bytes, content_type: str, context: dict[str, Any]
    ) -> VisionProviderResponse:
        del image_bytes, content_type, context
        if self.error is not None:
            raise self.error
        payload = deepcopy(self.payload)
        return VisionProviderResponse(
            payload=payload,
            raw_response={"mock": True, "result": payload},
            provider=self.name,
            model=self.model,
            input_tokens=0,
            output_tokens=0,
            estimated_cost=0,
        )
