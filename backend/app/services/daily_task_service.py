from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.health_activity import HealthPermissionState, HealthSyncState, SleepLog
from app.models.meal import MealLog
from app.models.supervision import DailyTask, HealthFollowup, ReminderPreference
from app.models.training import TrainingDay, TrainingPlan, WorkoutSession
from app.models.weight_log import WeightLog
from app.repositories.nutrition_repository import NutritionGoalRepository
from app.schemas.supervision import DailyTaskRead, ReminderPreferenceUpdate
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.health_activity_service import HealthActivityService


@dataclass(frozen=True)
class TaskTemplate:
    task_type: str
    title: str
    description: str
    priority: int
    scheduled_time: time | None
    source: str = "daily_engine"
    source_entity_id: str | None = None
    reminder_policy: dict[str, object] | None = None


class ReminderPreferenceService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get(self, user_id: UUID) -> ReminderPreference:
        value = await self.session.scalar(
            select(ReminderPreference).where(ReminderPreference.user_id == user_id)
        )
        if value is None:
            value = ReminderPreference(user_id=user_id)
            self.session.add(value)
            await self.session.commit()
            await self.session.refresh(value)
        return value

    async def update(self, user_id: UUID, payload: ReminderPreferenceUpdate) -> ReminderPreference:
        value = await self.get(user_id)
        for key, item in payload.model_dump().items():
            setattr(value, key, item)
        await self.session.commit()
        await self.session.refresh(value)
        return value


class DailyTaskEngine:
    """Idempotent task projection over existing health-domain records."""

    WORKOUT_WEEKDAYS: dict[int, tuple[int, ...]] = {
        1: (0,),
        2: (0, 3),
        3: (0, 2, 4),
        4: (0, 1, 3, 5),
        5: (0, 1, 2, 3, 4),
        6: (0, 1, 2, 3, 4, 5),
        7: (0, 1, 2, 3, 4, 5, 6),
    }

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.preferences = ReminderPreferenceService(session)
        self.nutrition = DailyNutritionService(session)

    async def generate(self, user_id: UUID, on_date: date | None = None) -> list[DailyTask]:
        timezone = await self.nutrition.timezone(user_id)
        reference = on_date or datetime.now(timezone).date()
        preference = await self.preferences.get(user_id)
        templates = await self._templates(user_id, reference, preference)
        existing = {
            item.dedup_key: item
            for item in (
                await self.session.scalars(
                    select(DailyTask).where(
                        DailyTask.user_id == user_id, DailyTask.task_date == reference
                    )
                )
            ).all()
        }
        for template in templates:
            dedup_key = self._dedup_key(template)
            if dedup_key in existing:
                continue
            task = DailyTask(
                user_id=user_id,
                task_date=reference,
                task_type=template.task_type,
                title=template.title,
                description=template.description,
                status="pending",
                priority=template.priority,
                scheduled_time=template.scheduled_time,
                source=template.source,
                source_entity_id=template.source_entity_id,
                reminder_policy=template.reminder_policy or {},
                dedup_key=dedup_key,
            )
            self.session.add(task)
            existing[dedup_key] = task
        await self.session.flush()
        await self._auto_complete(user_id, reference, list(existing.values()))
        await self._expire_old(user_id, reference)
        await self.session.commit()
        return await self.list_tasks(user_id, reference, refresh=False)

    async def list_tasks(
        self, user_id: UUID, on_date: date, *, refresh: bool = True
    ) -> list[DailyTask]:
        if refresh:
            return await self.generate(user_id, on_date)
        return list(
            (
                await self.session.scalars(
                    select(DailyTask)
                    .where(DailyTask.user_id == user_id, DailyTask.task_date == on_date)
                    .order_by(DailyTask.priority.desc(), DailyTask.scheduled_time.asc())
                )
            ).all()
        )

    async def set_status(self, user_id: UUID, task_id: UUID, status: str) -> DailyTask:
        task = await self.session.scalar(
            select(DailyTask).where(DailyTask.id == task_id, DailyTask.user_id == user_id)
        )
        if task is None:
            raise AppError("daily_task_not_found", "Daily task was not found.", 404)
        task.status = status
        task.completed_at = datetime.now(UTC) if status == "completed" else None
        await self.session.commit()
        await self.session.refresh(task)
        return task

    async def _templates(
        self, user_id: UUID, reference: date, preference: ReminderPreference
    ) -> list[TaskTemplate]:
        meal_windows = preference.meal_windows
        templates = [
            TaskTemplate(
                "weigh_in",
                "记录晨重",
                "起床如厕后、进食饮水前记录即可；关注连续趋势。",
                100,
                preference.weigh_time,
                reminder_policy={"cooldown_hours": 4, "channel": "local"},
            ),
            *[
                TaskTemplate(
                    f"{meal}_log",
                    f"记录{label}",
                    "按实际吃过的食物和大致份量记录，不要求完美。",
                    priority,
                    self._meal_reminder_time(meal_windows.get(meal), fallback),
                    reminder_policy={"cooldown_hours": 3, "channel": "server"},
                )
                for meal, label, priority, fallback in (
                    ("breakfast", "早餐", 75, time(10, 30)),
                    ("lunch", "午餐", 80, time(14, 30)),
                    ("dinner", "晚餐", 70, time(21, 30)),
                )
            ],
            TaskTemplate(
                "steps",
                "完成今日步数",
                "步数目标按近期基线渐进；恢复差时可以降低强度。",
                65,
                preference.step_check_time,
                reminder_policy={"cooldown_hours": 4, "channel": "server"},
            ),
            TaskTemplate(
                "nutrition_target",
                "关注今日营养",
                "优先保证蛋白质和规律饮食，不做惩罚性补偿。",
                55,
                time(19, 0),
                reminder_policy={"cooldown_hours": 4, "channel": "server"},
            ),
            TaskTemplate(
                "water",
                "记得适量饮水",
                "按口渴和活动情况补水；如医生限制饮水，请遵循医嘱。",
                25,
                time(15, 0),
                reminder_policy={"cooldown_hours": 4, "channel": "local"},
            ),
            TaskTemplate(
                "sleep",
                "准备休息",
                "为明天的计划留出足够睡眠时间。",
                70,
                preference.sleep_reminder_time,
                reminder_policy={"cooldown_hours": 12, "channel": "local"},
            ),
        ]
        workout = await self._workout_template(user_id, reference, preference)
        if workout:
            templates.append(workout)
        sync = await self._sync_template(user_id, reference)
        if sync:
            templates.append(sync)
        templates.extend(await self._followup_templates(user_id, reference))
        return templates

    async def _workout_template(
        self, user_id: UUID, reference: date, preference: ReminderPreference
    ) -> TaskTemplate | None:
        plan = await self.session.scalar(
            select(TrainingPlan)
            .where(
                TrainingPlan.user_id == user_id,
                TrainingPlan.active.is_(True),
                TrainingPlan.deleted_at.is_(None),
            )
            .order_by(TrainingPlan.created_at.desc())
        )
        if plan is None:
            return None
        weekdays = self.WORKOUT_WEEKDAYS.get(max(1, min(7, plan.sessions_per_week)), ())
        if reference.weekday() not in weekdays:
            return None
        session_index = weekdays.index(reference.weekday())
        days = list(
            (
                await self.session.scalars(
                    select(TrainingDay)
                    .where(TrainingDay.plan_id == plan.id)
                    .order_by(TrainingDay.order_index)
                )
            ).all()
        )
        training_day = days[session_index % len(days)] if days else None
        title = f"完成{training_day.name}" if training_day else f"完成{plan.name}训练"
        return TaskTemplate(
            "workout",
            title,
            "按当天恢复状态完成计划；身体不适时可以降级为轻活动。",
            90,
            preference.training_reminder_time,
            source="training_plan",
            source_entity_id=str(training_day.id if training_day else plan.id),
            reminder_policy={"cooldown_hours": 4, "channel": "local"},
        )

    async def _sync_template(self, user_id: UUID, reference: date) -> TaskTemplate | None:
        enabled = await self.session.scalar(
            select(func.count(HealthPermissionState.id)).where(
                HealthPermissionState.user_id == user_id,
                HealthPermissionState.provider == "healthkit",
                HealthPermissionState.enabled.is_(True),
            )
        )
        if not enabled:
            return None
        return TaskTemplate(
            "health_sync",
            "同步 Apple 健康",
            "打开 App 后同步近期步数、睡眠和活动摘要。",
            40,
            time(20, 30),
            reminder_policy={"cooldown_hours": 12, "channel": "server"},
        )

    async def _followup_templates(self, user_id: UUID, reference: date) -> list[TaskTemplate]:
        followups = list(
            (
                await self.session.scalars(
                    select(HealthFollowup).where(
                        HealthFollowup.user_id == user_id,
                        HealthFollowup.status == "confirmed",
                        HealthFollowup.recommended_date == reference,
                    )
                )
            ).all()
        )
        return [
            TaskTemplate(
                "lab_recheck",
                "健康复查提醒",
                "你确认的一项健康复查已到期，可按实际情况预约或稍后调整日期。",
                100,
                time(9, 0),
                source="health_followup",
                source_entity_id=str(item.id),
                reminder_policy={"cooldown_hours": 24, "channel": "server", "sensitive": True},
            )
            for item in followups
        ]

    async def _auto_complete(self, user_id: UUID, reference: date, tasks: list[DailyTask]) -> None:
        timezone = await self.nutrition.timezone(user_id)
        start, end = self.nutrition._utc_bounds(reference, reference, timezone)
        weights = await self.session.scalar(
            select(func.count(WeightLog.id)).where(
                WeightLog.user_id == user_id,
                WeightLog.measured_on == reference,
                WeightLog.deleted_at.is_(None),
            )
        )
        meals = {
            row[0]: row[1]
            for row in (
                await self.session.execute(
                    select(MealLog.meal_type, func.count(MealLog.id))
                    .where(
                        MealLog.user_id == user_id,
                        MealLog.eaten_at >= start,
                        MealLog.eaten_at < end,
                        MealLog.deleted_at.is_(None),
                    )
                    .group_by(MealLog.meal_type)
                )
            ).all()
        }
        workout = await self.session.scalar(
            select(func.count(WorkoutSession.id)).where(
                WorkoutSession.user_id == user_id,
                WorkoutSession.status == "completed",
                WorkoutSession.started_at >= start,
                WorkoutSession.started_at < end,
            )
        )
        sleep = await self.session.scalar(
            select(func.count(SleepLog.id)).where(
                SleepLog.user_id == user_id,
                SleepLog.sleep_end >= start - timedelta(hours=12),
                SleepLog.sleep_end < end,
            )
        )
        activity = await HealthActivityService(self.session).daily(user_id, reference)
        daily = await self.nutrition.daily(user_id, reference)
        goal = await NutritionGoalRepository(self.session).current(user_id, reference)
        sync = await self.session.scalar(
            select(func.max(HealthSyncState.last_sync_at)).where(
                HealthSyncState.user_id == user_id,
                HealthSyncState.provider == "healthkit",
            )
        )
        sync_complete = sync is not None and self._aware(sync) >= start
        completed_types = {
            "weigh_in": bool(weights),
            "breakfast_log": meals.get("breakfast", 0) > 0,
            "lunch_log": meals.get("lunch", 0) > 0,
            "dinner_log": meals.get("dinner", 0) > 0,
            "steps": activity.steps is not None and activity.steps >= activity.step_goal,
            "workout": bool(workout),
            "sleep": bool(sleep),
            "health_sync": sync_complete,
            "nutrition_target": bool(
                goal
                and daily.totals.protein >= goal.protein_target_g * Decimal("0.9")
                and daily.totals.calories >= Decimal(goal.calorie_target) * Decimal("0.8")
            ),
        }
        now = datetime.now(UTC)
        for task in tasks:
            if task.status == "pending" and completed_types.get(task.task_type, False):
                task.status = "completed"
                task.completed_at = now

    async def _expire_old(self, user_id: UUID, reference: date) -> None:
        old = list(
            (
                await self.session.scalars(
                    select(DailyTask).where(
                        DailyTask.user_id == user_id,
                        DailyTask.task_date < reference,
                        DailyTask.status == "pending",
                    )
                )
            ).all()
        )
        for task in old:
            task.status = "expired"

    @staticmethod
    def read(task: DailyTask) -> DailyTaskRead:
        return DailyTaskRead(
            id=task.id,
            date=task.task_date,
            task_type=task.task_type,
            title=task.title,
            description=task.description,
            status=task.status,
            priority=task.priority,
            scheduled_time=task.scheduled_time,
            completed_at=task.completed_at,
            source=task.source,
            source_entity_id=task.source_entity_id,
            reminder_policy=task.reminder_policy,
        )

    @staticmethod
    def _dedup_key(template: TaskTemplate) -> str:
        return f"{template.task_type}:{template.source_entity_id or 'daily'}"

    @staticmethod
    def _meal_reminder_time(window: list[str] | None, fallback: time) -> time:
        if not window or len(window) != 2:
            return fallback
        try:
            end = time.fromisoformat(window[1])
            return (datetime.combine(date.min, end) + timedelta(minutes=30)).time()
        except ValueError:
            return fallback

    @staticmethod
    def _aware(value: datetime) -> datetime:
        return value if value.tzinfo else value.replace(tzinfo=UTC)
