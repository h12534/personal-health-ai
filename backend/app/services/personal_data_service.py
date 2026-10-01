from __future__ import annotations

import csv
import io
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.health_activity import SleepLog, StepLog
from app.models.health_knowledge import LabReport
from app.models.health_profile import HealthProfile
from app.models.meal import MealLog
from app.models.meal_analysis import MealImage
from app.models.supervision import DailyTask, HealthFollowup, ReminderPreference
from app.models.training import WorkoutSession
from app.models.user import User
from app.models.weight_log import WeightLog
from app.providers.storage.base import StorageProvider


class PersonalDataService:
    FORMAT_VERSION = "phase7-v1"

    def __init__(self, session: AsyncSession, storage: StorageProvider) -> None:
        self.session = session
        self.storage = storage

    async def export_json(self, user_id: UUID) -> dict[str, object]:
        profile = await self.session.scalar(
            select(HealthProfile).where(HealthProfile.user_id == user_id)
        )
        weights = list(
            (
                await self.session.scalars(
                    select(WeightLog)
                    .where(WeightLog.user_id == user_id, WeightLog.deleted_at.is_(None))
                    .order_by(WeightLog.measured_on)
                )
            ).all()
        )
        meals = list(
            (
                await self.session.scalars(
                    select(MealLog)
                    .where(MealLog.user_id == user_id, MealLog.deleted_at.is_(None))
                    .order_by(MealLog.eaten_at)
                )
            ).all()
        )
        workouts = list(
            (
                await self.session.scalars(
                    select(WorkoutSession)
                    .where(WorkoutSession.user_id == user_id)
                    .order_by(WorkoutSession.started_at)
                )
            ).all()
        )
        sleeps = list(
            (
                await self.session.scalars(
                    select(SleepLog)
                    .where(SleepLog.user_id == user_id)
                    .order_by(SleepLog.sleep_start)
                )
            ).all()
        )
        steps = list(
            (
                await self.session.scalars(
                    select(StepLog).where(StepLog.user_id == user_id).order_by(StepLog.step_date)
                )
            ).all()
        )
        labs = list(
            (
                await self.session.scalars(
                    select(LabReport)
                    .where(LabReport.user_id == user_id, LabReport.deleted_at.is_(None))
                    .order_by(LabReport.report_date)
                )
            ).all()
        )
        tasks = list(
            (
                await self.session.scalars(
                    select(DailyTask)
                    .where(DailyTask.user_id == user_id)
                    .order_by(DailyTask.task_date)
                )
            ).all()
        )
        followups = list(
            (
                await self.session.scalars(
                    select(HealthFollowup).where(HealthFollowup.user_id == user_id)
                )
            ).all()
        )
        preference = await self.session.scalar(
            select(ReminderPreference).where(ReminderPreference.user_id == user_id)
        )
        return {
            "exported_at": datetime.now(UTC).isoformat(),
            "format_version": self.FORMAT_VERSION,
            "data": {
                "profile": self._profile(profile),
                "weights": [
                    {
                        "date": item.measured_on.isoformat(),
                        "weight_kg": float(item.weight_kg),
                        "source": item.source,
                        "note": item.note,
                    }
                    for item in weights
                ],
                "meals": [
                    {
                        "id": str(item.id),
                        "meal_type": item.meal_type,
                        "eaten_at": self._datetime(item.eaten_at),
                        "source": item.source,
                        "note": item.note,
                        "totals": {
                            "calories": float(item.total_calories),
                            "protein_g": float(item.total_protein),
                            "carbs_g": float(item.total_carbs),
                            "fat_g": float(item.total_fat),
                            "fiber_g": float(item.total_fiber),
                        },
                        "items": [
                            {
                                "name": child.food_name_snapshot,
                                "amount": float(child.amount),
                                "unit": child.amount_unit,
                                "weight_g": float(child.weight_g),
                                "calories": float(child.calories),
                                "protein_g": float(child.protein),
                            }
                            for child in item.items
                            if child.deleted_at is None
                        ],
                    }
                    for item in meals
                ],
                "workouts": [
                    {
                        "id": str(item.id),
                        "started_at": self._datetime(item.started_at),
                        "ended_at": self._datetime(item.ended_at),
                        "duration_min": item.duration_min,
                        "status": item.status,
                        "source": item.source,
                        "sets": [
                            {
                                "exercise_id": str(child.exercise_id),
                                "set_number": child.set_number,
                                "weight_kg": float(child.weight_kg),
                                "reps": child.reps,
                                "completed": child.completed,
                            }
                            for child in item.sets
                        ],
                    }
                    for item in workouts
                ],
                "sleep": [
                    {
                        "start": self._datetime(item.sleep_start),
                        "end": self._datetime(item.sleep_end),
                        "duration_min": item.duration_min,
                        "quality": item.quality,
                        "source": item.source,
                    }
                    for item in sleeps
                ],
                "steps": [
                    {
                        "date": item.step_date.isoformat(),
                        "steps": item.steps,
                        "distance_km": self._number(item.distance_km),
                        "source": item.source,
                    }
                    for item in steps
                ],
                "lab_reports": [
                    {
                        "id": str(item.id),
                        "date": item.report_date.isoformat(),
                        "hospital": item.hospital_name,
                        "review_status": item.review_status,
                        "results": [
                            {
                                "test_code": child.test_code,
                                "test_name": child.test_name,
                                "value": self._number(child.value_numeric) or child.value_text,
                                "unit": child.unit,
                                "reference": child.reference_text,
                                "flag": child.flag,
                            }
                            for child in item.results
                            if child.deleted_at is None
                        ],
                    }
                    for item in labs
                ],
                "daily_tasks": [
                    {
                        "date": item.task_date.isoformat(),
                        "type": item.task_type,
                        "title": item.title,
                        "status": item.status,
                        "completed_at": self._datetime(item.completed_at),
                    }
                    for item in tasks
                ],
                "health_followups": [
                    {
                        "test_code": item.lab_test_code,
                        "reason": item.reason,
                        "recommended_date": item.recommended_date.isoformat(),
                        "status": item.status,
                    }
                    for item in followups
                ],
                "reminder_preferences": (
                    {
                        "enabled": preference.enabled,
                        "mode": preference.mode,
                        "weigh_time": preference.weigh_time.isoformat(),
                        "meal_windows": preference.meal_windows,
                        "do_not_disturb_start": preference.do_not_disturb_start.isoformat(),
                        "do_not_disturb_end": preference.do_not_disturb_end.isoformat(),
                    }
                    if preference
                    else None
                ),
            },
        }

    async def export_csv(self, user_id: UUID) -> str:
        bundle = await self.export_json(user_id)
        data = bundle["data"]
        assert isinstance(data, dict)
        output = io.StringIO()
        writer = csv.writer(output, lineterminator="\n")
        writer.writerow(["category", "date_or_time", "name", "value", "unit", "details"])
        for weight in self._dict_list(data.get("weights")):
            writer.writerow(["weight", weight["date"], "weight", weight["weight_kg"], "kg", ""])
        for meal in self._dict_list(data.get("meals")):
            raw_totals = meal.get("totals")
            totals: dict[str, Any] = raw_totals if isinstance(raw_totals, dict) else {}
            writer.writerow(
                [
                    "meal",
                    meal["eaten_at"],
                    meal["meal_type"],
                    totals.get("calories"),
                    "kcal",
                    f"protein_g={totals.get('protein_g')}",
                ]
            )
        for workout in self._dict_list(data.get("workouts")):
            writer.writerow(
                [
                    "workout",
                    workout["started_at"],
                    workout["status"],
                    workout["duration_min"],
                    "minutes",
                    "",
                ]
            )
        for sleep in self._dict_list(data.get("sleep")):
            writer.writerow(["sleep", sleep["end"], "sleep", sleep["duration_min"], "minutes", ""])
        for step in self._dict_list(data.get("steps")):
            writer.writerow(["steps", step["date"], "steps", step["steps"], "steps", ""])
        for report in self._dict_list(data.get("lab_reports")):
            for result in self._dict_list(report.get("results")):
                writer.writerow(
                    [
                        "lab",
                        report["date"],
                        result["test_name"],
                        result["value"],
                        result["unit"],
                        f"reference={result['reference']}; flag={result['flag']}",
                    ]
                )
        return output.getvalue()

    async def delete_all(self, user_id: UUID, confirmation: str) -> None:
        if confirmation != "DELETE MY DATA":
            raise AppError(
                "data_delete_confirmation_required",
                "Type DELETE MY DATA to confirm permanent deletion.",
                422,
            )
        image_keys = list(
            (
                await self.session.scalars(
                    select(MealImage.object_key).where(MealImage.user_id == user_id)
                )
            ).all()
        )
        lab_keys = list(
            (
                await self.session.scalars(
                    select(LabReport.original_file_id).where(
                        LabReport.user_id == user_id,
                        LabReport.original_file_id.is_not(None),
                    )
                )
            ).all()
        )
        user = await self.session.get(User, user_id)
        if user is None:
            raise AppError("user_not_found", "User was not found.", 404)
        await self.session.execute(delete(User).where(User.id == user_id))
        await self.session.commit()
        for key in [*image_keys, *lab_keys]:
            if key:
                await self.storage.delete(key)

    @staticmethod
    def _profile(profile: HealthProfile | None) -> dict[str, object] | None:
        if profile is None:
            return None
        return {
            "birth_date": profile.birth_date.isoformat() if profile.birth_date else None,
            "sex": profile.sex,
            "height_cm": PersonalDataService._number(profile.height_cm),
            "target_weight_kg": PersonalDataService._number(profile.target_weight_kg),
            "waist_cm": PersonalDataService._number(profile.waist_cm),
            "body_fat_percent": PersonalDataService._number(profile.body_fat_percent),
            "primary_goal": profile.primary_goal,
            "timezone": profile.timezone,
            "known_health_risks": profile.known_health_risks,
            "medications": profile.medications,
        }

    @staticmethod
    def _number(value: Decimal | None) -> float | None:
        return float(value) if value is not None else None

    @staticmethod
    def _datetime(value: datetime | None) -> str | None:
        return value.isoformat() if value is not None else None

    @staticmethod
    def _dict_list(value: Any) -> list[dict[str, Any]]:
        if not isinstance(value, list):
            return []
        return [item for item in value if isinstance(item, dict)]
