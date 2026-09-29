from dataclasses import dataclass
from hashlib import sha256
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.errors import AppError

ALLOWED_TYPES = {
    "image/jpeg": "JPEG",
    "image/png": "PNG",
    "image/webp": "WEBP",
}


@dataclass(frozen=True, slots=True)
class SanitizedImage:
    data: bytes
    content_type: str
    suffix: str
    width: int
    height: int
    sha256: str


class ImageValidationService:
    def __init__(self, max_bytes: int, max_pixels: int, max_dimension: int) -> None:
        self.max_bytes = max_bytes
        self.max_pixels = max_pixels
        self.max_dimension = max_dimension

    @staticmethod
    def _magic_format(data: bytes) -> str | None:
        if data.startswith(b"\xff\xd8\xff"):
            return "JPEG"
        if data.startswith(b"\x89PNG\r\n\x1a\n"):
            return "PNG"
        if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
            return "WEBP"
        return None

    def validate_and_sanitize(
        self, data: bytes, claimed_content_type: str | None
    ) -> SanitizedImage:
        if not data:
            raise AppError("empty_image", "Please choose a non-empty meal image.", 422)
        if len(data) > self.max_bytes:
            raise AppError("image_too_large", "Meal images must be 10 MB or smaller.", 413)
        normalized_type = (claimed_content_type or "").split(";", 1)[0].strip().lower()
        if normalized_type == "image/jpg":
            normalized_type = "image/jpeg"
        expected_format = ALLOWED_TYPES.get(normalized_type)
        detected_format = self._magic_format(data)
        if expected_format is None or detected_format is None or expected_format != detected_format:
            raise AppError(
                "invalid_image_type",
                "Only valid JPEG, PNG, and WEBP meal images are accepted.",
                415,
            )
        try:
            with Image.open(BytesIO(data)) as source:
                width, height = source.size
                if (
                    width < 1
                    or height < 1
                    or width > self.max_dimension
                    or height > self.max_dimension
                    or width * height > self.max_pixels
                ):
                    raise AppError(
                        "image_dimensions_unsupported",
                        "Meal image dimensions exceed the safe processing limit.",
                        422,
                    )
                source.load()
                oriented = ImageOps.exif_transpose(source)
                if oriented.mode in {"RGBA", "LA"}:
                    background = Image.new("RGB", oriented.size, "white")
                    alpha = oriented.getchannel("A")
                    background.paste(oriented.convert("RGB"), mask=alpha)
                    clean = background
                else:
                    clean = oriented.convert("RGB")
                output = BytesIO()
                clean.save(output, format="JPEG", quality=90, optimize=True)
                sanitized = output.getvalue()
        except AppError:
            raise
        except (Image.DecompressionBombError, UnidentifiedImageError, OSError, ValueError) as exc:
            raise AppError("invalid_image", "The uploaded file is not a safe image.", 422) from exc
        return SanitizedImage(
            data=sanitized,
            content_type="image/jpeg",
            suffix="jpg",
            width=width,
            height=height,
            sha256=sha256(sanitized).hexdigest(),
        )
