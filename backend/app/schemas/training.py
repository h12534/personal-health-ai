from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ExerciseRead(BaseModel):
    id: UUID
    name: str
    normalized_name: str
    category: str
    movement_pattern: str
    primary_muscles: list[str]
    secondary_muscles: list[str]
    equipment: list[str]
    difficulty: str
    instructions: str
    setup_instructions: list[str]
    execution_cues: list[str]
    common_mistakes: list[str]
    safety_notes: list[str]
    video_url: str | None
    image_url: str | None
    unilateral: bool
    bodyweight: bool
    compound: bool
    active: bool

    model_config = ConfigDict(from_attributes=True)


class TrainingExerciseWrite(BaseModel):
    exercise_id: UUID
    order_index: int = Field(ge=0, le=30)
    target_sets: int = Field(default=3, ge=1, le=10)
    target_rep_min: int = Field(default=8, ge=1, le=100)
    target_rep_max: int = Field(default=12, ge=1, le=100)
    target_weight_kg: Decimal | None = Field(default=None, ge=0, le=1000)
    target_rpe: Decimal | None = Field(default=None, ge=1, le=10)
    target_rir: Decimal | None = Field(default=Decimal("2"), ge=0, le=9)
    rest_seconds: int = Field(default=120, ge=15, le=900)
    tempo: str | None = Field(default=None, max_length=32)
    notes: str | None = Field(default=None, max_length=1000)
    progression_type: Literal[
        "double_progression", "weight_progression", "rep_progression", "volume_progression"
    ] = "double_progression"

    @model_validator(mode="after")
    def validate_rep_range(self) -> "TrainingExerciseWrite":
        if self.target_rep_min > self.target_rep_max:
            raise ValueError("target_rep_min must not exceed target_rep_max")
        return self


class TrainingDayWrite(BaseModel):
    day_number: int = Field(ge=1, le=7)
    name: str = Field(min_length=1, max_length=120)
    focus: str = Field(min_length=1, max_length=120)
    estimated_duration_min: int = Field(default=60, ge=15, le=240)
    notes: str | None = Field(default=None, max_length=2000)
    order_index: int = Field(ge=0, le=6)
    exercises: list[TrainingExerciseWrite] = Field(default_factory=list, max_length=20)


class TrainingPlanCreate(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    goal: str = Field(default="fat_loss_muscle_retention", max_length=64)
    difficulty: Literal["beginner", "novice", "intermediate", "advanced"] = "beginner"
    weeks: int = Field(default=8, ge=1, le=52)
    sessions_per_week: int = Field(default=3, ge=1, le=7)
    active: bool = True
    days: list[TrainingDayWrite] = Field(default_factory=list, max_length=7)


class TrainingPlanUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=160)
    goal: str | None = Field(default=None, max_length=64)
    difficulty: Literal["beginner", "novice", "intermediate", "advanced"] | None = None
    weeks: int | None = Field(default=None, ge=1, le=52)
    active: bool | None = None


class TrainingPlanGenerate(BaseModel):
    goal: str = Field(default="fat_loss_muscle_retention", max_length=64)
    experience: Literal["beginner", "novice", "intermediate", "advanced"] = "beginner"
    days_per_week: Literal[2, 3, 4] = 3
    equipment: list[str] = Field(
        default_factory=lambda: ["machine", "dumbbell", "cable", "bodyweight"],
        max_length=20,
    )
    session_duration_min: int = Field(default=60, ge=30, le=120)
    limitations: list[str] = Field(default_factory=list, max_length=20)
    preferences: list[str] = Field(default_factory=list, max_length=30)
    weeks: int = Field(default=8, ge=1, le=52)
    name: str | None = Field(default=None, max_length=160)


class TrainingExerciseRead(BaseModel):
    id: UUID
    training_day_id: UUID
    exercise_id: UUID
    order_index: int
    target_sets: int
    target_rep_min: int
    target_rep_max: int
    target_weight_kg: Decimal | None
    target_rpe: Decimal | None
    target_rir: Decimal | None
    rest_seconds: int
    tempo: str | None
    notes: str | None
    progression_type: str
    exercise: ExerciseRead

    model_config = ConfigDict(from_attributes=True)


class TrainingDayRead(BaseModel):
    id: UUID
    plan_id: UUID
    day_number: int
    name: str
    focus: str
    estimated_duration_min: int
    notes: str | None
    order_index: int
    exercises: list[TrainingExerciseRead]

    model_config = ConfigDict(from_attributes=True)


class TrainingPlanRead(BaseModel):
    id: UUID
    user_id: UUID
    name: str
    goal: str
    difficulty: str
    weeks: int
    sessions_per_week: int
    active: bool
    days: list[TrainingDayRead]
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class WorkoutSetCreate(BaseModel):
    id: UUID | None = None
    exercise_id: UUID
    set_number: int = Field(ge=1, le=100)
    set_type: Literal["warmup", "working", "backoff", "drop", "failure", "bodyweight"] = "working"
    weight_kg: Decimal = Field(default=Decimal("0"), ge=0, le=1000)
    reps: int = Field(default=0, ge=0, le=500)
    rpe: Decimal | None = Field(default=None, ge=1, le=10)
    rir: Decimal | None = Field(default=None, ge=0, le=9)
    completed: bool = True
    rest_seconds: int | None = Field(default=None, ge=0, le=1800)
    notes: str | None = Field(default=None, max_length=1000)
    idempotency_key: str | None = Field(default=None, min_length=8, max_length=128)

    @model_validator(mode="after")
    def one_effort_input(self) -> "WorkoutSetCreate":
        if self.rpe is not None and self.rir is not None:
            expected = Decimal("10") - self.rir
            if abs(expected - self.rpe) > Decimal("1"):
                raise ValueError("rpe and rir are inconsistent")
        return self


class WorkoutSetUpdate(BaseModel):
    weight_kg: Decimal | None = Field(default=None, ge=0, le=1000)
    reps: int | None = Field(default=None, ge=0, le=500)
    rpe: Decimal | None = Field(default=None, ge=1, le=10)
    rir: Decimal | None = Field(default=None, ge=0, le=9)
    completed: bool | None = None
    rest_seconds: int | None = Field(default=None, ge=0, le=1800)
    notes: str | None = Field(default=None, max_length=1000)


class WorkoutSessionCreate(BaseModel):
    id: UUID | None = None
    training_day_id: UUID | None = None
    started_at: datetime | None = None
    energy_level: int | None = Field(default=None, ge=1, le=5)
    notes: str | None = Field(default=None, max_length=2000)
    source: str = Field(default="manual", max_length=32)
    idempotency_key: str | None = Field(default=None, min_length=8, max_length=128)


class WorkoutSetRead(BaseModel):
    id: UUID
    session_id: UUID
    exercise_id: UUID
    set_number: int
    set_type: str
    weight_kg: Decimal
    reps: int
    rpe: Decimal | None
    rir: Decimal | None
    completed: bool
    rest_seconds: int | None
    notes: str | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class WorkoutSessionRead(BaseModel):
    id: UUID
    user_id: UUID
    training_day_id: UUID | None
    started_at: datetime
    ended_at: datetime | None
    duration_min: int | None
    status: str
    session_rpe: Decimal | None
    energy_level: int | None
    notes: str | None
    source: str
    sets: list[WorkoutSetRead]
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class WorkoutComplete(BaseModel):
    ended_at: datetime | None = None
    session_rpe: Decimal | None = Field(default=None, ge=1, le=10)
    energy_level: int | None = Field(default=None, ge=1, le=5)
    notes: str | None = Field(default=None, max_length=2000)


class PRRead(BaseModel):
    id: UUID
    exercise_id: UUID
    workout_set_id: UUID | None
    pr_type: str
    value: Decimal
    achieved_at: datetime
    confidence: str

    model_config = ConfigDict(from_attributes=True)


class WorkoutSummary(BaseModel):
    session: WorkoutSessionRead
    total_sets: int
    effective_sets: int
    volume_load: Decimal
    prs: list[PRRead]
    message: str


class ProgressPoint(BaseModel):
    date: date
    max_weight_kg: Decimal
    max_reps: int
    estimated_1rm_kg: Decimal
    volume_load: Decimal
    e1rm_confidence: Literal["high", "normal", "low"]


class ExerciseProgressRead(BaseModel):
    exercise_id: UUID
    period_days: int
    points: list[ProgressPoint]


class ProgressionSuggestion(BaseModel):
    action: Literal["increase_weight", "increase_reps", "maintain", "reduce_load", "reduce_set"]
    suggested_weight_kg: Decimal
    suggested_sets: int
    reason: str
    rule_version: str = "progression_v1"


class TrainingAdjustmentApply(BaseModel):
    exercise_id: UUID
    suggested_weight_kg: Decimal = Field(ge=0, le=1000)
    reason: str = Field(min_length=1, max_length=2000)
    idempotency_key: str = Field(min_length=8, max_length=128)
    evidence_snapshot: dict[str, object] = Field(default_factory=dict)


class PainLogWrite(BaseModel):
    workout_session_id: UUID | None = None
    exercise_id: UUID | None = None
    body_area: str = Field(min_length=1, max_length=64)
    severity: int = Field(ge=1, le=10)
    symptoms: list[str] = Field(default_factory=list, max_length=20)
    note: str | None = Field(default=None, max_length=1000)
    acute: bool = False


class TrainingChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)


class TrainingSuggestedAction(BaseModel):
    type: Literal[
        "start_workout",
        "open_exercise",
        "apply_progression",
        "reschedule_plan",
        "open_recovery",
        "none",
    ]
    label: str
    target_id: str | None = None
    payload: dict[str, object] = Field(default_factory=dict)


class TrainingChatResponse(BaseModel):
    intent: str
    message: str
    suggested_actions: list[TrainingSuggestedAction]
    safety_notice: str | None
    risk_level: Literal["normal", "caution", "urgent"]
    provider: str
    model: str
    used_context: list[str]
    rule_version: str = "training_coach_v1"


class WeeklyTrainingReviewRead(BaseModel):
    date_from: date
    date_to: date
    planned_sessions: int
    completed_sessions: int
    effective_sets: int
    volume_load: Decimal
    personal_records: list[str]
    average_steps: int | None
    average_sleep_minutes: int | None
    recovery_status: Literal["good", "normal", "reduced", "insufficient_data"]
    pain_logs: int
    observations: list[str]
    next_actions: list[str]
