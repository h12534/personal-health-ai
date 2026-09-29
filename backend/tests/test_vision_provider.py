from typing import Any

from app.schemas.meal_analysis import VisionMealResult


def test_vision_json_schema_is_compatible_with_strict_structured_outputs() -> None:
    schema = VisionMealResult.model_json_schema()
    _assert_all_object_fields_required(schema)
    for definition in schema.get("$defs", {}).values():
        _assert_all_object_fields_required(definition)


def _assert_all_object_fields_required(schema: dict[str, Any]) -> None:
    if schema.get("type") != "object":
        return
    properties = schema.get("properties", {})
    assert schema.get("additionalProperties") is False
    assert set(schema.get("required", [])) == set(properties)
