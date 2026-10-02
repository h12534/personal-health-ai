import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_production_rejects_development_secret() -> None:
    with pytest.raises(ValidationError):
        Settings(
            app_env="production", app_secret_key="development-secret-change-before-production-32"
        )


def test_production_accepts_strong_secret() -> None:
    settings = Settings(
        app_env="production",
        app_secret_key="x" * 48,
        database_url="postgresql+asyncpg://health:encoded-secret@postgres:5432/health_os",
        public_base_url="https://api.personal-health.test",
    )
    assert settings.is_production


def test_staging_has_the_same_secret_database_and_https_guards() -> None:
    with pytest.raises(ValidationError):
        Settings(app_env="staging")
    settings = Settings(
        app_env="staging",
        app_secret_key="s" * 48,
        database_url="postgresql+asyncpg://health:secret@postgres:5432/health_staging",
        public_base_url="https://staging-api.personal-health.test",
    )
    assert settings.is_deployed is True
    assert settings.is_production is False


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("app_secret_key", "replace-with-a-real-production-secret-value"),
        ("database_url", "sqlite+aiosqlite:///./production.db"),
        ("public_base_url", "https://api.example.com"),
    ],
)
def test_production_rejects_placeholders(field: str, value: str) -> None:
    values = {
        "app_env": "production",
        "app_secret_key": "x" * 48,
        "database_url": "postgresql+asyncpg://health:secret@postgres:5432/health_os",
        "public_base_url": "https://health.example.test",
    }
    values[field] = value
    with pytest.raises(ValueError):
        Settings(**values)
