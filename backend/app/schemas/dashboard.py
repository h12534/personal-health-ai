from datetime import date

from pydantic import BaseModel, Field

from app.schemas.supervision import DailyTaskRead


class DashboardToday(BaseModel):
    date: date
    today_weight_kg: float | None
    average_7d_kg: float | None
    week_change_kg: float | None
    calories_consumed: int = 0
    calories_target: int | None = None
    protein_g: float = 0
    protein_target_g: float | None = None
    carbs_g: float = 0
    carbs_target_g: float | None = None
    fat_g: float = 0
    fat_target_g: float | None = None
    fiber_g: float = 0
    fiber_target_g: float | None = None
    steps: int | None = None
    steps_target: int = 5000
    water_ml: int = 0
    sleep_hours: float | None = None
    training_completed: bool = False
    morning_weight_completed: bool = False
    breakfast_logged: bool = False
    lunch_logged: bool = False
    dinner_logged: bool = False
    ai_next_action: str
    key_tasks: list[DailyTaskRead] = Field(default_factory=list)
