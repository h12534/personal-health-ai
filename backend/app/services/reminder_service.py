from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.health_activity import RecoverySnapshot
from app.models.supervision import DailyTask, NotificationLog, PushDevice, ReminderPreference
from app.providers.push.base import PushMessage, PushProvider
from app.schemas.supervision import ReminderDecisionRead
from app.services.daily_nutrition_service import DailyNutritionService
from app.services.health_activity_service import HealthActivityService


@dataclass(frozen=True)
class ReminderCopy:
    title: str
    body: str


class NotificationPrivacy:
    """Lock-screen copy must never contain diagnoses or sensitive lab values."""

    SENSITIVE_TASKS = {"lab_recheck"}

    @classmethod
    def redact(cls, task: DailyTask, copy: ReminderCopy) -> ReminderCopy:
        if task.task_type in cls.SENSITIVE_TASKS or task.reminder_policy.get("sensitive"):
            return ReminderCopy("健康提醒", "你有一项健康复查提醒。")
        return copy


class ReminderEngine:
    COOLDOWN_HOURS = {
        "weigh_in": 4,
        "breakfast_log": 3,
        "lunch_log": 3,
        "dinner_log": 3,
        "nutrition_target": 4,
        "steps": 4,
        "workout": 4,
        "water": 4,
        "sleep": 12,
        "health_sync": 12,
        "lab_recheck": 24,
        "custom": 4,
    }
    MAX_DAILY = {"gentle": 2, "standard": 4, "strict": 6}

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.nutrition = DailyNutritionService(session)

    async def decide(
        self,
        task: DailyTask,
        preference: ReminderPreference,
        *,
        now: datetime | None = None,
    ) -> ReminderDecisionRead:
        timezone = await self.nutrition.timezone(task.user_id)
        instant = now or datetime.now(UTC)
        local_now = instant.astimezone(timezone)
        if not preference.enabled:
            return self._no(task, "reminders_disabled")
        if task.status != "pending":
            return self._no(task, "task_not_pending")
        if local_now.date() != task.task_date:
            return self._no(task, "outside_task_date")
        if self._inside_dnd(
            local_now.time(), preference.do_not_disturb_start, preference.do_not_disturb_end
        ):
            return self._no(task, "do_not_disturb")
        if task.scheduled_time and local_now.time() < task.scheduled_time:
            return self._no(task, "not_due")
        if preference.mode == "gentle" and task.priority < 70:
            return self._no(task, "gentle_mode_low_priority")
        sent_today = await self.session.scalar(
            select(func.count(NotificationLog.id)).where(
                NotificationLog.user_id == task.user_id,
                NotificationLog.sent_at >= datetime.combine(local_now.date(), time.min, timezone),
                NotificationLog.status == "sent",
            )
        )
        if (sent_today or 0) >= self.MAX_DAILY.get(preference.mode, 4):
            return self._no(task, "daily_limit")
        raw_cooldown = task.reminder_policy.get(
            "cooldown_hours", self.COOLDOWN_HOURS.get(task.task_type, 4)
        )
        cooldown = raw_cooldown if isinstance(raw_cooldown, int) else 4
        last_sent = await self.session.scalar(
            select(func.max(NotificationLog.sent_at)).where(
                NotificationLog.task_id == task.id,
                NotificationLog.status == "sent",
            )
        )
        if last_sent and self._aware(last_sent) > instant - timedelta(hours=cooldown):
            return self._no(task, "cooldown")
        copy = NotificationPrivacy.redact(task, await self._copy(task))
        channel = str(task.reminder_policy.get("channel", "server"))
        return ReminderDecisionRead(
            should_send=True,
            reason="due",
            channel=channel,
            title=copy.title,
            body=copy.body,
            task_id=task.id,
        )

    async def _copy(self, task: DailyTask) -> ReminderCopy:
        if task.task_type == "weigh_in":
            return ReminderCopy("晨重提醒", "今天晨重还没有记录；方便时称一次即可。")
        if task.task_type.endswith("_log"):
            meal = {"breakfast_log": "早餐", "lunch_log": "午餐", "dinner_log": "晚餐"}.get(
                task.task_type, "这一餐"
            )
            return ReminderCopy("饮食记录", f"{meal}还没有记录，方便时补记实际吃过的内容。")
        if task.task_type == "steps":
            activity = await HealthActivityService(self.session).daily(task.user_id, task.task_date)
            remaining = max(0, activity.step_goal - (activity.steps or 0))
            recovery = await self.session.scalar(
                select(RecoverySnapshot).where(
                    RecoverySnapshot.user_id == task.user_id,
                    RecoverySnapshot.snapshot_date == task.task_date,
                )
            )
            if recovery and recovery.status in {"reduced", "rest"}:
                return ReminderCopy("今日活动", "今天恢复一般，轻松走动即可，不必勉强追目标。")
            return ReminderCopy(
                "步数提醒", f"今天距离步数目标还有约 {remaining} 步；如果方便，可以散步一会儿。"
            )
        if task.task_type == "workout":
            recovery = await self.session.scalar(
                select(RecoverySnapshot).where(
                    RecoverySnapshot.user_id == task.user_id,
                    RecoverySnapshot.snapshot_date == task.task_date,
                )
            )
            if recovery and recovery.status in {"reduced", "rest"}:
                return ReminderCopy("训练计划", "今天恢复一般，可以降低训练强度或改成轻活动。")
            return ReminderCopy("训练计划", "今天有训练计划；方便时开始，完成一次就够。")
        if task.task_type == "sleep":
            return ReminderCopy("睡眠准备", "现在差不多可以开始放松，为明天留出足够睡眠。")
        if task.task_type == "nutrition_target":
            daily = await self.nutrition.daily(task.user_id, task.task_date)
            return ReminderCopy(
                "今日营养",
                (
                    "今天蛋白质进度偏低，后续可优先选择蛋、奶、肉、鱼或豆制品。"
                    if daily.totals.protein < 60
                    else "今天的饮食记录已接近完成，按饥饿感正常安排即可。"
                ),
            )
        if task.task_type == "health_sync":
            return ReminderCopy("健康数据同步", "打开 App 后可同步近期 Apple 健康摘要。")
        if task.task_type == "water":
            return ReminderCopy("饮水提醒", "如果现在口渴，可以适量补水。")
        return ReminderCopy(task.title, task.description)

    @staticmethod
    def _inside_dnd(current: time, start: time, end: time) -> bool:
        if start == end:
            return False
        if start < end:
            return start <= current < end
        return current >= start or current < end

    @staticmethod
    def _aware(value: datetime) -> datetime:
        return value if value.tzinfo else value.replace(tzinfo=UTC)

    @staticmethod
    def _no(task: DailyTask, reason: str) -> ReminderDecisionRead:
        return ReminderDecisionRead(should_send=False, reason=reason, task_id=task.id)


class NotificationService:
    def __init__(self, session: AsyncSession, push: PushProvider) -> None:
        self.session = session
        self.push = push

    async def send(self, task: DailyTask, decision: ReminderDecisionRead) -> NotificationLog:
        now = datetime.now(UTC)
        window = now.strftime("%Y%m%d%H")
        dedup_key = f"task:{task.id}:{decision.channel}:{window}"
        existing = await self.session.scalar(
            select(NotificationLog).where(NotificationLog.dedup_key == dedup_key)
        )
        if existing and existing.status != "failed":
            return existing
        if existing:
            log = existing
            log.status = "prepared"
            log.reason = "retry_after_failure"
            log.provider = self.push.name
        else:
            log = NotificationLog(
                user_id=task.user_id,
                task_id=task.id,
                notification_type=task.task_type,
                channel=decision.channel or "server",
                scheduled_at=now,
                status="prepared",
                reason=decision.reason,
                provider=self.push.name,
                dedup_key=dedup_key,
            )
            self.session.add(log)
        if decision.channel == "local":
            log.status = "delegated_local"
            await self.session.commit()
            return log
        device = await self.session.scalar(
            select(PushDevice)
            .where(PushDevice.user_id == task.user_id, PushDevice.active.is_(True))
            .order_by(PushDevice.last_seen_at.desc())
        )
        if device is None:
            log.status = "skipped"
            log.reason = "no_active_push_device"
            await self.session.commit()
            return log
        result = await self.push.send(
            PushMessage(
                token=device.token,
                title=decision.title or "健康提醒",
                body=decision.body or "你有一项待办。",
                category="HEALTH_TASK",
                data={"task_id": str(task.id), "action": "open"},
            )
        )
        log.status = "sent" if result.accepted else "failed"
        log.sent_at = now if result.accepted else None
        log.reason = result.error
        await self.session.commit()
        return log
