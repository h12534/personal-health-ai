from functools import lru_cache

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=("../.env", ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "Personal Health OS"
    app_env: str = "development"
    app_secret_key: str = "development-secret-change-before-production-32"
    database_url: str = "sqlite+aiosqlite:///./health_os.db"
    redis_url: str = "redis://localhost:6379/0"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 30
    cors_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])
    upload_dir: str = "../storage/uploads"
    max_upload_bytes: int = 10 * 1024 * 1024
    ai_provider: str = "disabled"
    ai_base_url: str | None = None
    ai_api_key: str | None = None
    ai_text_model: str | None = None
    ai_vision_model: str | None = None
    ai_embedding_model: str | None = None
    ai_request_timeout_seconds: int = 60

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        if self.is_production and self.app_secret_key.startswith("development-secret"):
            raise ValueError("APP_SECRET_KEY must be replaced in production")
        if self.is_production and len(self.app_secret_key) < 32:
            raise ValueError("APP_SECRET_KEY must contain at least 32 characters")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
