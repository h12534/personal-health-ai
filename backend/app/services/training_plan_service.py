from collections.abc import Iterable
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import AppError
from app.models.training import (
    Exercise,
    TrainingAdjustment,
    TrainingDay,
    TrainingExercise,
    TrainingPlan,
)
from app.schemas.training import (
    TrainingAdjustmentApply,
    TrainingDayWrite,
    TrainingExerciseWrite,
    TrainingPlanCreate,
    TrainingPlanGenerate,
    TrainingPlanUpdate,
)
from app.services.exercise_service import ExerciseService

PLAN_LOAD = (
    selectinload(TrainingPlan.days)
    .selectinload(TrainingDay.exercises)
    .selectinload(TrainingExercise.exercise)
)


class TrainingPlanGenerator:
    TEMPLATES: dict[int, list[tuple[str, str, list[list[str]]]]] = {
        2: [
            (
                "全身 A",
                "全身力量",
                [
                    ["腿举", "深蹲", "史密斯深蹲"],
                    ["器械推胸", "哑铃卧推", "卧推"],
                    ["高位下拉", "引体向上"],
                    ["坐姿划船", "单臂划船"],
                    ["死虫", "平板支撑"],
                ],
            ),
            (
                "全身 B",
                "全身力量",
                [
                    ["罗马尼亚硬拉", "臀桥"],
                    ["腿弯举", "腿屈伸"],
                    ["上斜卧推", "肩推"],
                    ["坐姿划船", "高位下拉"],
                    ["农夫走", "卷腹"],
                ],
            ),
        ],
        3: [
            (
                "训练 A",
                "全身力量",
                [
                    ["腿举", "深蹲", "史密斯深蹲"],
                    ["器械推胸", "哑铃卧推", "卧推"],
                    ["高位下拉", "引体向上"],
                    ["坐姿划船", "单臂划船"],
                    ["肩推", "侧平举"],
                    ["死虫", "平板支撑"],
                ],
            ),
            (
                "训练 B",
                "全身力量",
                [
                    ["罗马尼亚硬拉", "臀桥"],
                    ["腿弯举", "腿屈伸"],
                    ["上斜卧推", "器械推胸"],
                    ["高位下拉", "引体向上"],
                    ["坐姿划船", "面拉"],
                    ["卷腹", "死虫"],
                ],
            ),
            (
                "训练 C",
                "全身力量",
                [
                    ["史密斯深蹲", "腿举", "深蹲"],
                    ["臀桥", "罗马尼亚硬拉"],
                    ["哑铃卧推", "肩推"],
                    ["单臂划船", "坐姿划船"],
                    ["高位下拉", "面拉"],
                    ["农夫走", "平板支撑"],
                ],
            ),
        ],
        4: [
            (
                "上肢 A",
                "上肢力量",
                [
                    ["器械推胸", "卧推", "哑铃卧推"],
                    ["高位下拉", "引体向上"],
                    ["坐姿划船", "单臂划船"],
                    ["肩推"],
                    ["侧平举", "面拉"],
                ],
            ),
            (
                "下肢 A",
                "下肢力量",
                [
                    ["腿举", "深蹲", "史密斯深蹲"],
                    ["罗马尼亚硬拉", "臀桥"],
                    ["腿弯举"],
                    ["腿屈伸"],
                    ["死虫", "平板支撑"],
                ],
            ),
            (
                "上肢 B",
                "上肢力量",
                [
                    ["上斜卧推", "哑铃卧推"],
                    ["坐姿划船", "单臂划船"],
                    ["高位下拉", "引体向上"],
                    ["面拉", "侧平举"],
                    ["二头弯举"],
                    ["三头下压"],
                ],
            ),
            (
                "下肢 B",
                "下肢力量",
                [
                    ["史密斯深蹲", "腿举", "深蹲"],
                    ["臀桥", "罗马尼亚硬拉"],
                    ["腿弯举"],
                    ["农夫走"],
                    ["卷腹", "死虫"],
                ],
            ),
        ],
    }

    @classmethod
    def build_days(
        cls, payload: TrainingPlanGenerate, exercises: Iterable[Exercise]
    ) -> list[TrainingDayWrite]:
        by_name = {item.name: item for item in exercises}
        allowed_equipment = set(payload.equipment)
        limitation_text = " ".join(payload.limitations).lower()
        blocked_patterns: set[str] = set()
        if any(value in limitation_text for value in ("膝", "knee")):
            blocked_patterns.update({"squat", "lunge"})
        if any(value in limitation_text for value in ("腰", "背", "back", "lower back")):
            blocked_patterns.add("hinge")
        if any(value in limitation_text for value in ("肩", "shoulder")):
            blocked_patterns.update({"vertical_push", "horizontal_push"})
        preferred = set(payload.preferences)
        result: list[TrainingDayWrite] = []
        for day_index, (name, focus, slots) in enumerate(cls.TEMPLATES[payload.days_per_week]):
            selected: list[Exercise] = []
            for alternatives in slots:
                candidates = [by_name[value] for value in alternatives if value in by_name]
                candidates = [
                    item
                    for item in candidates
                    if item.movement_pattern not in blocked_patterns
                    and (not allowed_equipment or allowed_equipment.intersection(item.equipment))
                ]
                candidates.sort(
                    key=lambda item: (item.name not in preferred, alternatives.index(item.name))
                )
                if candidates:
                    selected.append(candidates[0])
            if len(selected) < 4:
                raise AppError(
                    "plan_generation_constraints",
                    "当前设备与身体限制无法组成安全、均衡的训练日，请增加可用设备或调整限制。",
                    422,
                )
            max_exercises = 5 if payload.session_duration_min < 50 else 6
            writes = [
                TrainingExerciseWrite(
                    exercise_id=item.id,
                    order_index=index,
                    target_sets=2 if payload.experience == "beginner" else 3,
                    target_rep_min=8,
                    target_rep_max=12,
                    target_rir=(Decimal("3") if payload.experience == "beginner" else Decimal("2")),
                    rest_seconds=150 if item.compound else 90,
                    progression_type="double_progression",
                )
                for index, item in enumerate(selected[:max_exercises])
            ]
            result.append(
                TrainingDayWrite(
                    day_number=day_index + 1,
                    name=name,
                    focus=focus,
                    estimated_duration_min=payload.session_duration_min,
                    notes="默认保留 2–3 次余力；疼痛或明显不适时停止并记录。",
                    order_index=day_index,
                    exercises=writes,
                )
            )
        return result


class TrainingPlanService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, user_id: UUID, payload: TrainingPlanCreate) -> TrainingPlan:
        plan = TrainingPlan(
            user_id=user_id,
            name=payload.name,
            goal=payload.goal,
            difficulty=payload.difficulty,
            weeks=payload.weeks,
            sessions_per_week=payload.sessions_per_week,
            active=payload.active,
        )
        for day_payload in payload.days:
            day = TrainingDay(
                day_number=day_payload.day_number,
                name=day_payload.name,
                focus=day_payload.focus,
                estimated_duration_min=day_payload.estimated_duration_min,
                notes=day_payload.notes,
                order_index=day_payload.order_index,
            )
            day.exercises = [
                TrainingExercise(**exercise.model_dump()) for exercise in day_payload.exercises
            ]
            plan.days.append(day)
        self.session.add(plan)
        await self.session.commit()
        return await self.get(user_id, plan.id)

    async def generate(self, user_id: UUID, payload: TrainingPlanGenerate) -> TrainingPlan:
        exercise_service = ExerciseService(self.session)
        exercises = await exercise_service.list_all()
        days = TrainingPlanGenerator.build_days(payload, exercises)
        name = payload.name or (
            f"{payload.days_per_week} 天"
            + ("全身训练" if payload.days_per_week < 4 else "上下肢训练")
        )
        return await self.create(
            user_id,
            TrainingPlanCreate(
                name=name,
                goal=payload.goal,
                difficulty=payload.experience,
                weeks=payload.weeks,
                sessions_per_week=payload.days_per_week,
                active=True,
                days=days,
            ),
        )

    async def list_all(self, user_id: UUID) -> list[TrainingPlan]:
        statement = (
            select(TrainingPlan)
            .where(TrainingPlan.user_id == user_id, TrainingPlan.deleted_at.is_(None))
            .options(PLAN_LOAD)
            .order_by(TrainingPlan.active.desc(), TrainingPlan.created_at.desc())
        )
        plans = list((await self.session.scalars(statement)).unique().all())
        self._sort(plans)
        return plans

    async def get(self, user_id: UUID, plan_id: UUID) -> TrainingPlan:
        statement = (
            select(TrainingPlan)
            .where(
                TrainingPlan.id == plan_id,
                TrainingPlan.user_id == user_id,
                TrainingPlan.deleted_at.is_(None),
            )
            .options(PLAN_LOAD)
        )
        plan = (await self.session.scalars(statement)).unique().one_or_none()
        if plan is None:
            raise AppError("training_plan_not_found", "Training plan was not found.", 404)
        self._sort([plan])
        return plan

    async def update(
        self, user_id: UUID, plan_id: UUID, payload: TrainingPlanUpdate
    ) -> TrainingPlan:
        plan = await self.get(user_id, plan_id)
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(plan, field, value)
        await self.session.commit()
        return await self.get(user_id, plan_id)

    async def apply_progression(
        self, user_id: UUID, payload: TrainingAdjustmentApply
    ) -> TrainingExercise:
        duplicate = await self.session.scalar(
            select(TrainingAdjustment).where(
                TrainingAdjustment.user_id == user_id,
                TrainingAdjustment.idempotency_key == payload.idempotency_key,
            )
        )
        if duplicate is not None and duplicate.training_exercise_id is not None:
            existing = await self.session.scalar(
                select(TrainingExercise)
                .where(TrainingExercise.id == duplicate.training_exercise_id)
                .options(selectinload(TrainingExercise.exercise))
            )
            if existing is not None:
                return existing

        statement = (
            select(TrainingExercise)
            .join(TrainingDay, TrainingDay.id == TrainingExercise.training_day_id)
            .join(TrainingPlan, TrainingPlan.id == TrainingDay.plan_id)
            .where(
                TrainingPlan.user_id == user_id,
                TrainingPlan.active.is_(True),
                TrainingPlan.deleted_at.is_(None),
                TrainingExercise.exercise_id == payload.exercise_id,
            )
            .options(selectinload(TrainingExercise.exercise))
            .order_by(TrainingDay.order_index, TrainingExercise.order_index)
            .limit(1)
        )
        target = await self.session.scalar(statement)
        if target is None:
            raise AppError(
                "training_exercise_not_found",
                "The exercise is not present in the active training plan.",
                404,
            )
        previous_weight = target.target_weight_kg
        target.target_weight_kg = payload.suggested_weight_kg
        self.session.add(
            TrainingAdjustment(
                user_id=user_id,
                training_exercise_id=target.id,
                adjustment_type="progression_weight",
                status="applied",
                previous_value={
                    "target_weight_kg": (
                        str(previous_weight) if previous_weight is not None else None
                    )
                },
                proposed_value={"target_weight_kg": str(payload.suggested_weight_kg)},
                reason=payload.reason,
                evidence_snapshot=payload.evidence_snapshot,
                rule_version="progression_v1",
                idempotency_key=payload.idempotency_key,
                applied_at=datetime.now(UTC),
            )
        )
        await self.session.commit()
        return target

    @staticmethod
    def _sort(plans: list[TrainingPlan]) -> None:
        for plan in plans:
            plan.days.sort(key=lambda item: item.order_index)
            for day in plan.days:
                day.exercises.sort(key=lambda item: item.order_index)


class PlanRescheduleService:
    @staticmethod
    def reschedule(
        planned_dates: list[date],
        missed_date: date,
        available_dates: list[date],
        minimum_recovery_hours: int = 48,
    ) -> list[date]:
        kept = [value for value in planned_dates if value < missed_date]
        candidates = sorted(
            {value for value in [*planned_dates, *available_dates] if value > missed_date}
        )
        required = len(planned_dates) - len(kept)
        for candidate in candidates:
            if len(kept) >= len(planned_dates):
                break
            if kept and (candidate - kept[-1]).days * 24 < minimum_recovery_hours:
                continue
            kept.append(candidate)
        return kept[: len(planned_dates)] if required > 0 else planned_dates
