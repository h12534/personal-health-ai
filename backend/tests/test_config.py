import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_production_rejects_development_secret() -> None:
    with pytest.raises(ValidationError):
        Settings(
            app_env="production", app_secret_key="development-secret-change-before-production-32"
        )


def test_production_accepts_strong_secret() -> None:
    settings = Settings(app_env="production", app_secret_key="x" * 48)
    assert settings.is_production
