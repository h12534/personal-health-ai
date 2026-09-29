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
    vision_provider: str = "mock"
    vision_base_url: str | None = None
    vision_api_key: str | None = None
    vision_model: str = "mock-meal-v1"
    vision_prompt_version: str = "meal_v1"
    vision_timeout_seconds: int = Field(default=45, ge=5, le=180)
    vision_max_attempts: int = Field(default=2, ge=1, le=3)
    vision_daily_limit: int = Field(default=50, ge=1, le=1000)
    vision_max_pixels: int = Field(default=36_000_000, ge=1_000_000)
    vision_max_dimension: int = Field(default=12_000, ge=1000, le=30_000)
    vision_async_enabled: bool = False
    vision_reanalysis_limit: int = Field(default=3, ge=0, le=10)
    vision_raw_response_max_chars: int = Field(default=100_000, ge=1000)
    vision_raw_response_retention_days: int = Field(default=7, ge=0, le=90)
    meal_analysis_draft_ttl_hours: int = Field(default=24, ge=1, le=168)
    meal_image_retention_days: int = Field(default=30, ge=0, le=365)
    ai_usage_retention_days: int = Field(default=365, ge=30, le=3650)
    coach_provider: str = "mock"
    coach_base_url: str | None = None
    coach_api_key: str | None = None
    coach_model: str = "mock-coach-v1"
    coach_prompt_version: str = "diet_coach_v1"
    coach_timeout_seconds: int = Field(default=45, ge=5, le=180)
    coach_max_attempts: int = Field(default=2, ge=1, le=3)
    coach_daily_limit: int = Field(default=100, ge=1, le=1000)

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        if self.is_production and self.app_secret_key.startswith("development-secret"):
            raise ValueError("APP_SECRET_KEY must be replaced in production")
        if self.is_production and len(self.app_secret_key) < 32:
            raise ValueError("APP_SECRET_KEY must contain at least 32 characters")
        if self.vision_provider == "openai_compatible":
            if not self.vision_base_url or not self.vision_api_key:
                raise ValueError(
                    "VISION_BASE_URL and VISION_API_KEY are required for openai_compatible"
                )
        if self.coach_provider == "openai_compatible":
            if not self.coach_base_url or not self.coach_api_key:
                raise ValueError(
                    "COACH_BASE_URL and COACH_API_KEY are required for openai_compatible"
                )
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
