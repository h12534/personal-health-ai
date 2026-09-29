from io import BytesIO

import pytest
from PIL import Image

from app.core.errors import AppError
from app.services.image_validation_service import ImageValidationService


def _png(width: int = 32, height: int = 32) -> bytes:
    output = BytesIO()
    Image.new("RGB", (width, height), "green").save(output, format="PNG")
    return output.getvalue()


def test_image_is_decoded_resaved_as_jpeg_and_metadata_removed() -> None:
    result = ImageValidationService(1024 * 1024, 1_000_000, 1000).validate_and_sanitize(
        _png(), "image/png"
    )
    assert result.content_type == "image/jpeg"
    assert result.suffix == "jpg"
    assert result.data.startswith(b"\xff\xd8\xff")
    with Image.open(BytesIO(result.data)) as image:
        assert image.getexif() == {}


@pytest.mark.parametrize(
    ("service", "data", "content_type", "code"),
    [
        (ImageValidationService(10, 1_000_000, 1000), _png(), "image/png", "image_too_large"),
        (
            ImageValidationService(1024 * 1024, 100, 1000),
            _png(20, 20),
            "image/png",
            "image_dimensions_unsupported",
        ),
        (
            ImageValidationService(1024 * 1024, 1_000_000, 1000),
            _png(),
            "image/webp",
            "invalid_image_type",
        ),
    ],
)
def test_image_security_limits(
    service: ImageValidationService,
    data: bytes,
    content_type: str,
    code: str,
) -> None:
    with pytest.raises(AppError) as captured:
        service.validate_and_sanitize(data, content_type)
    assert captured.value.code == code
