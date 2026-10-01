from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

HealthDataType = Literal[
    "steps",
    "walking_running_distance",
    "active_energy_burned",
    "resting_heart_rate",
    "sleep",
    "workouts",
]


class DailyActivityRead(BaseModel):
    date: date
    steps: int | None
    distance_km: Decimal | None
    active_energy_kcal: Decimal | None
    resting_heart_rate: int | None
    source: str | None
    step_goal: int
    message: str


class HealthSummaryWrite(BaseModel):
    provider: Literal["healthkit", "manual", "mock"] = "healthkit"
    data_type: HealthDataType
    source_record_id: str = Field(min_length=1, max_length=200)
    recorded_date: date | None = None
    steps: int | None = Field(default=None, ge=0, le=500000)
    distance_km: Decimal | None = Field(default=None, ge=0, le=1000)
    active_energy_kcal: Decimal | None = Field(default=None, ge=0, le=20000)
    resting_heart_rate: int | None = Field(default=None, ge=20, le=250)
    sleep_start: datetime | None = None
    sleep_end: datetime | None = None
    sleep_stages: list[dict[str, object]] = Field(default_factory=list)
    sleep_quality: int | None = Field(default=None, ge=1, le=5)
    workout_start: datetime | None = None
    workout_end: datetime | None = None
    workout_type: str | None = Field(default=None, max_length=64)
    cursor: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def validate_payload(self) -> "HealthSummaryWrite":
        if self.data_type == "steps" and self.recorded_date is None:
            raise ValueError("recorded_date is required for steps")
        if self.data_type == "sleep" and (self.sleep_start is None or self.sleep_end is None):
            raise ValueError("sleep_start and sleep_end are required for sleep")
        if self.data_type == "workouts" and (
            self.workout_start is None or self.workout_end is None
        ):
            raise ValueError("workout_start and workout_end are required for workouts")
        return self


class HealthSyncResult(BaseModel):
    created: bool
    duplicate: bool
    data_type: str
    source_record_id: str


class HealthSyncStatusRead(BaseModel):
    data_type: str
    last_sync_at: datetime | None
    status: str
    error_summary: str | None


class SleepRead(BaseModel):
    id: UUID
    sleep_start: datetime
    sleep_end: datetime
    duration_min: int
    source: str
    sleep_stages: list[dict[str, object]]
    quality: int | None
    source_record_id: str | None

    model_config = ConfigDict(from_attributes=True)


class PermissionWrite(BaseModel):
    data_type: HealthDataType
    enabled: bool
    authorization_status: Literal[
        "not_requested", "authorized", "denied", "unavailable", "unknown"
    ] = "not_requested"


class PermissionRead(BaseModel):
    data_type: str
    enabled: bool
    authorization_status: str
    requested_at: datetime | None


class RecoveryInput(BaseModel):
    subjective_fatigue: int | None = Field(default=None, ge=1, le=5)
    pain_severity: int | None = Field(default=None, ge=0, le=10)


class RecoveryRead(BaseModel):
    date: date
    status: Literal["good", "normal", "reduced", "insufficient_data"]
    reasons: list[str]
    sleep_duration_min: int | None
    resting_heart_rate: int | None
    message: str
