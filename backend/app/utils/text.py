import re
import unicodedata


def normalize_food_name(value: str) -> str:
    """Normalize searchable food text without destroying CJK characters."""
    normalized = unicodedata.normalize("NFKC", value).strip().casefold()
    return re.sub(r"[\s\-_]+", "", normalized)
