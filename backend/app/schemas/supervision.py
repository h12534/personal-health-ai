from datetime import date, datetime, time
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

TaskStatus = Literal["pending", "completed", "skipped", "expired", "cancelled"]
ReminderMode = Literal["gentle", "standard", "strict"]


class DailyTaskRead(BaseModel):
    id: UUID
    date: date
    task_type: str
    title: str
    description: str
    status: str
    priority: int
    scheduled_time: time | None
    completed_at: datetime | None
    source: str
    source_entity_id: str | None
    reminder_policy: dict[str, object]


class TaskStatusUpdate(BaseModel):
    status: TaskStatus


class ReminderPreferenceRead(BaseModel):
    enabled: bool
    mode: str
    weigh_time: time
    meal_windows: dict[str, list[str]]
    training_reminder_time: time
    sleep_reminder_time: time
    step_check_time: time
    do_not_disturb_start: time
    do_not_disturb_end: time
    weekly_report_day: int
    monthly_report_day: int
    local_notifications_enabled: bool
    server_notifications_enabled: bool


class ReminderPreferenceUpdate(BaseModel):
    enabled: bool = True
    mode: ReminderMode = "standard"
    weigh_time: time = time(8, 0)
    meal_windows: dict[str, list[str]] = Field(
        default_factory=lambda: {
            "breakfast": ["07:00", "10:00"],
            "lunch": ["11:00", "14:00"],
            "dinner": ["17:00", "21:00"],
        }
    )
    training_reminder_time: time = time(18, 0)
    sleep_reminder_time: time = time(23, 0)
    step_check_time: time = time(20, 0)
    do_not_disturb_start: time = time(23, 0)
    do_not_disturb_end: time = time(7, 30)
    weekly_report_day: int = Field(default=6, ge=0, le=6)
    monthly_report_day: int = Field(default=1, ge=1, le=28)
    local_notifications_enabled: bool = False
    server_notifications_enabled: bool = True

    @field_validator("meal_windows")
    @classmethod
    def validate_windows(cls, value: dict[str, list[str]]) -> dict[str, list[str]]:
        required = {"breakfast", "lunch", "dinner"}
        if set(value) != required:
            raise ValueError("meal windows must define breakfast, lunch, and dinner")
        for window in value.values():
            if len(window) != 2:
                raise ValueError("each meal window must contain start and end")
            for item in window:
                try:
                    time.fromisoformat(item)
                except ValueError as exc:
                    raise ValueError("meal window times must use HH:MM") from exc
        return value


class ReminderDecisionRead(BaseModel):
    should_send: bool
    reason: str
    channel: str | None = None
    title: str | None = None
    body: str | None = None
    task_id: UUID | None = None


class HealthFollowupCreate(BaseModel):
    lab_test_code: str | None = Field(default=None, max_length=80)
    reason: str = Field(min_length=2, max_length=1000)
    recommended_date: date
    source: str = Field(default="user", max_length=40)
    source_entity_id: str | None = Field(default=None, max_length=128)


class HealthFollowupRead(BaseModel):
    id: UUID
    lab_test_code: str | None
    reason: str
    recommended_date: date
    status: str
    source: str
    source_entity_id: str | None
    confirmed_at: datetime | None


class HealthReportRead(BaseModel):
    id: UUID
    report_type: str
    period_start: date
    period_end: date
    metrics: dict[str, object]
    summary: str
    next_actions: list[str]
    rule_version: str
    prompt_version: str
    provider: str
    model: str
    created_at: datetime


class TimelineEventRead(BaseModel):
    id: str
    event_type: str
    category: str
    occurred_at: datetime
    title: str
    summary: str
    metadata: dict[str, object] = Field(default_factory=dict)


class CrossDomainRead(BaseModel):
    date_from: date
    date_to: date
    series: dict[str, list[dict[str, object]]]
    observations: list[str]
    disclaimer: str


class PushDeviceUpsert(BaseModel):
    device_id: str = Field(min_length=4, max_length=160)
    platform: Literal["ios", "android"] = "ios"
    environment: Literal["dev", "staging", "prod"] = "dev"
    token: str = Field(min_length=8, max_length=512)


class ExportBundleRead(BaseModel):
    exported_at: datetime
    format_version: str
    data: dict[str, object]


class DeleteMyDataRequest(BaseModel):
    confirmation: str


class NotificationLogRead(BaseModel):
    id: UUID
    task_id: UUID | None
    notification_type: str
    channel: str
    scheduled_at: datetime
    sent_at: datetime | None
    status: str
    reason: str | None
    provider: str
    interaction: str | None
