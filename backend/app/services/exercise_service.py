from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.training import Exercise
from app.scripts.seed_exercises import seed_exercises


class ExerciseService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def ensure_seeded(self) -> None:
        if await self.session.scalar(select(Exercise.id).limit(1)) is None:
            await seed_exercises(self.session)

    async def list_all(
        self,
        *,
        movement_pattern: str | None = None,
        equipment: str | None = None,
        difficulty: str | None = None,
    ) -> list[Exercise]:
        await self.ensure_seeded()
        statement = select(Exercise).where(Exercise.active.is_(True))
        if movement_pattern:
            statement = statement.where(Exercise.movement_pattern == movement_pattern)
        if difficulty:
            statement = statement.where(Exercise.difficulty == difficulty)
        result = list((await self.session.scalars(statement.order_by(Exercise.name))).all())
        if equipment:
            result = [item for item in result if equipment in item.equipment]
        return result

    async def search(self, query: str) -> list[Exercise]:
        await self.ensure_seeded()
        normalized = query.strip().lower()
        if not normalized:
            return []
        pattern = f"%{normalized}%"
        statement = (
            select(Exercise)
            .where(
                Exercise.active.is_(True),
                or_(
                    Exercise.normalized_name.ilike(pattern),
                    Exercise.name.ilike(pattern),
                    Exercise.instructions.ilike(pattern),
                ),
            )
            .order_by(Exercise.name)
            .limit(30)
        )
        return list((await self.session.scalars(statement)).all())
