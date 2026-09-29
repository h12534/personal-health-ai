from typing import cast
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.diet_coach import (
    Canteen,
    CanteenDish,
    CanteenStall,
    CoachConversation,
    DietAdjustment,
    HungerLog,
    PersonalDietaryMemory,
    SavedMeal,
)


class DietCoachRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def adjustment(self, user_id: UUID, adjustment_id: UUID) -> DietAdjustment | None:
        return cast(
            DietAdjustment | None,
            await self.session.scalar(
                select(DietAdjustment).where(
                    DietAdjustment.id == adjustment_id, DietAdjustment.user_id == user_id
                )
            ),
        )

    async def adjustment_by_hash(self, user_id: UUID, snapshot_hash: str) -> DietAdjustment | None:
        return cast(
            DietAdjustment | None,
            await self.session.scalar(
                select(DietAdjustment)
                .where(
                    DietAdjustment.user_id == user_id,
                    DietAdjustment.input_snapshot_hash == snapshot_hash,
                    DietAdjustment.status == "pending",
                )
                .order_by(DietAdjustment.created_at.desc())
                .limit(1)
            ),
        )

    async def latest_decided_adjustment(self, user_id: UUID) -> DietAdjustment | None:
        return cast(
            DietAdjustment | None,
            await self.session.scalar(
                select(DietAdjustment)
                .where(DietAdjustment.user_id == user_id, DietAdjustment.decided_at.is_not(None))
                .order_by(DietAdjustment.decided_at.desc())
                .limit(1)
            ),
        )

    async def hunger_logs(self, user_id: UUID, limit: int = 50) -> list[HungerLog]:
        values = await self.session.scalars(
            select(HungerLog)
            .where(HungerLog.user_id == user_id)
            .order_by(HungerLog.logged_at.desc())
            .limit(limit)
        )
        return list(values.all())

    async def canteens(self, user_id: UUID) -> list[Canteen]:
        values = await self.session.scalars(
            select(Canteen)
            .options(selectinload(Canteen.stalls).selectinload(CanteenStall.dishes))
            .where(Canteen.user_id == user_id, Canteen.is_active.is_(True))
            .order_by(Canteen.name)
        )
        return list(values.unique().all())

    async def canteen(self, user_id: UUID, canteen_id: UUID) -> Canteen | None:
        return cast(
            Canteen | None,
            await self.session.scalar(
                select(Canteen)
                .options(selectinload(Canteen.stalls).selectinload(CanteenStall.dishes))
                .where(
                    Canteen.id == canteen_id,
                    Canteen.user_id == user_id,
                    Canteen.is_active.is_(True),
                )
            ),
        )

    async def stall(self, user_id: UUID, stall_id: UUID) -> CanteenStall | None:
        return cast(
            CanteenStall | None,
            await self.session.scalar(
                select(CanteenStall)
                .join(Canteen, Canteen.id == CanteenStall.canteen_id)
                .options(selectinload(CanteenStall.dishes))
                .where(
                    CanteenStall.id == stall_id,
                    Canteen.user_id == user_id,
                    Canteen.is_active.is_(True),
                    CanteenStall.is_active.is_(True),
                )
            ),
        )

    async def dish(self, user_id: UUID, dish_id: UUID) -> CanteenDish | None:
        return cast(
            CanteenDish | None,
            await self.session.scalar(
                select(CanteenDish)
                .join(CanteenStall, CanteenStall.id == CanteenDish.stall_id)
                .join(Canteen, Canteen.id == CanteenStall.canteen_id)
                .where(
                    CanteenDish.id == dish_id,
                    Canteen.user_id == user_id,
                    CanteenDish.is_available.is_(True),
                )
            ),
        )

    async def memories(self, user_id: UUID) -> list[PersonalDietaryMemory]:
        values = await self.session.scalars(
            select(PersonalDietaryMemory)
            .where(
                PersonalDietaryMemory.user_id == user_id,
                PersonalDietaryMemory.is_active.is_(True),
            )
            .order_by(PersonalDietaryMemory.kind, PersonalDietaryMemory.created_at)
        )
        return list(values.all())

    async def memory(self, user_id: UUID, memory_id: UUID) -> PersonalDietaryMemory | None:
        return cast(
            PersonalDietaryMemory | None,
            await self.session.scalar(
                select(PersonalDietaryMemory).where(
                    PersonalDietaryMemory.id == memory_id,
                    PersonalDietaryMemory.user_id == user_id,
                    PersonalDietaryMemory.is_active.is_(True),
                )
            ),
        )

    async def saved_meals(self, user_id: UUID) -> list[SavedMeal]:
        values = await self.session.scalars(
            select(SavedMeal)
            .options(selectinload(SavedMeal.items))
            .where(SavedMeal.user_id == user_id, SavedMeal.deleted_at.is_(None))
            .order_by(SavedMeal.updated_at.desc())
        )
        return list(values.unique().all())

    async def saved_meal(self, user_id: UUID, saved_meal_id: UUID) -> SavedMeal | None:
        return cast(
            SavedMeal | None,
            await self.session.scalar(
                select(SavedMeal)
                .options(selectinload(SavedMeal.items))
                .where(
                    SavedMeal.id == saved_meal_id,
                    SavedMeal.user_id == user_id,
                    SavedMeal.deleted_at.is_(None),
                )
            ),
        )

    async def conversation(self, user_id: UUID, conversation_id: UUID) -> CoachConversation | None:
        return cast(
            CoachConversation | None,
            await self.session.scalar(
                select(CoachConversation)
                .options(selectinload(CoachConversation.messages))
                .where(
                    CoachConversation.id == conversation_id,
                    CoachConversation.user_id == user_id,
                )
            ),
        )
