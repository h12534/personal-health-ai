from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field


class WeightCreate(BaseModel):
    measured_on: date
    weight_kg: Decimal = Field(ge=20, le=500, decimal_places=2)
    note: str | None = Field(default=None, max_length=1000)
    source: str = Field(default="manual", max_length=32)


class WeightUpdate(BaseModel):
    measured_on: date | None = None
    weight_kg: Decimal | None = Field(default=None, ge=20, le=500, decimal_places=2)
    note: str | None = Field(default=None, max_length=1000)


class WeightRead(WeightCreate):
    id: UUID
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class WeightTrendPoint(BaseModel):
    measured_on: date
    weight_kg: float
    moving_average_7d: float


class WeightTrendSummary(BaseModel):
    points: list[WeightTrendPoint]
    latest_weight_kg: float | None
    average_7d_kg: float | None
    previous_7d_average_kg: float | None
    week_change_kg: float | None
    rate_kg_per_week: float | None
