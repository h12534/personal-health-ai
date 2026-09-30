from datetime import datetime
from uuid import UUID

from sqlalchemy import case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.food import FoodAlias, FoodFavorite, FoodItem
from app.models.meal import MealItem, MealLog


class FoodRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    @staticmethod
    def _visible(user_id: UUID):  # type: ignore[no-untyped-def]
        return (
            FoodItem.deleted_at.is_(None),
            FoodItem.is_active.is_(True),
            or_(FoodItem.owner_user_id.is_(None), FoodItem.owner_user_id == user_id),
        )

    async def by_id(self, user_id: UUID, food_id: UUID) -> FoodItem | None:
        result = await self.session.scalar(
            select(FoodItem)
            .options(selectinload(FoodItem.aliases))
            .where(FoodItem.id == food_id, *self._visible(user_id))
        )
        return result

    async def custom_by_id(self, user_id: UUID, food_id: UUID) -> FoodItem | None:
        result = await self.session.scalar(
            select(FoodItem)
            .options(selectinload(FoodItem.aliases))
            .where(
                FoodItem.id == food_id,
                FoodItem.owner_user_id == user_id,
                FoodItem.is_custom.is_(True),
                FoodItem.deleted_at.is_(None),
            )
        )
        return result

    async def by_source(self, source: str, source_id: str) -> FoodItem | None:
        result = await self.session.scalar(
            select(FoodItem)
            .options(selectinload(FoodItem.aliases))
            .where(FoodItem.source == source, FoodItem.source_id == source_id)
        )
        return result

    async def all_for_matching(self, user_id: UUID, limit: int = 1000) -> list[FoodItem]:
        foods = await self.session.scalars(
            select(FoodItem)
            .options(selectinload(FoodItem.aliases))
            .where(*self._visible(user_id))
            .order_by(FoodItem.is_custom.desc(), FoodItem.normalized_name)
            .limit(limit)
        )
        return list(foods.all())

    async def search(
        self,
        user_id: UUID,
        normalized_query: str = "",
        category: str | None = None,
        limit: int = 30,
    ) -> list[FoodItem]:
        recent = (
            select(MealItem.food_id, func.max(MealLog.eaten_at).label("last_used"))
            .join(MealLog, MealLog.id == MealItem.meal_id)
            .where(
                MealLog.user_id == user_id,
                MealLog.deleted_at.is_(None),
                MealItem.deleted_at.is_(None),
                MealItem.food_id.is_not(None),
            )
            .group_by(MealItem.food_id)
            .subquery()
        )
        query = (
            select(FoodItem)
            .outerjoin(FoodAlias, FoodAlias.food_id == FoodItem.id)
            .outerjoin(
                FoodFavorite,
                (FoodFavorite.food_id == FoodItem.id) & (FoodFavorite.user_id == user_id),
            )
            .outerjoin(recent, recent.c.food_id == FoodItem.id)
            .options(selectinload(FoodItem.aliases))
            .where(*self._visible(user_id))
        )
        if category:
            query = query.where(FoodItem.category == category)
        if normalized_query:
            pattern = f"%{normalized_query}%"
            query = query.where(
                or_(
                    FoodItem.normalized_name.ilike(pattern),
                    func.coalesce(FoodItem.brand, "").ilike(pattern),
                    FoodAlias.normalized_alias.ilike(pattern),
                )
            )
            relevance = case(
                (FoodItem.normalized_name == normalized_query, 0),
                (FoodAlias.normalized_alias == normalized_query, 1),
                (FoodItem.normalized_name.ilike(f"{normalized_query}%"), 2),
                else_=3,
            )
        else:
            relevance = case((FoodItem.is_custom.is_(True), 0), else_=1)
        query = query.order_by(
            case((FoodFavorite.id.is_not(None), 0), else_=1),
            case((recent.c.last_used.is_not(None), 0), else_=1),
            recent.c.last_used.desc(),
            relevance,
            FoodItem.normalized_name,
        ).limit(limit * 5)
        rows = (await self.session.scalars(query)).all()
        deduplicated: list[FoodItem] = []
        seen: set[UUID] = set()
        for food in rows:
            if food.id not in seen:
                deduplicated.append(food)
                seen.add(food.id)
            if len(deduplicated) == limit:
                break
        return deduplicated

    async def favorite_ids(self, user_id: UUID, food_ids: list[UUID]) -> set[UUID]:
        if not food_ids:
            return set()
        values = await self.session.scalars(
            select(FoodFavorite.food_id).where(
                FoodFavorite.user_id == user_id, FoodFavorite.food_id.in_(food_ids)
            )
        )
        return set(values.all())

    async def favorites(self, user_id: UUID) -> list[tuple[FoodItem, datetime]]:
        rows = await self.session.execute(
            select(FoodItem, FoodFavorite.created_at)
            .join(FoodFavorite, FoodFavorite.food_id == FoodItem.id)
            .options(selectinload(FoodItem.aliases))
            .where(FoodFavorite.user_id == user_id, *self._visible(user_id))
            .order_by(FoodFavorite.created_at.desc())
        )
        return [(food, created_at) for food, created_at in rows.all()]

    async def recent(self, user_id: UUID, limit: int = 20) -> list[FoodItem]:
        recent = (
            select(MealItem.food_id, func.max(MealLog.eaten_at).label("last_used"))
            .join(MealLog, MealLog.id == MealItem.meal_id)
            .where(
                MealLog.user_id == user_id,
                MealLog.deleted_at.is_(None),
                MealItem.deleted_at.is_(None),
                MealItem.food_id.is_not(None),
            )
            .group_by(MealItem.food_id)
            .subquery()
        )
        foods = await self.session.scalars(
            select(FoodItem)
            .join(recent, recent.c.food_id == FoodItem.id)
            .options(selectinload(FoodItem.aliases))
            .where(*self._visible(user_id))
            .order_by(recent.c.last_used.desc())
            .limit(limit)
        )
        return list(foods.all())

    async def favorite(self, user_id: UUID, food_id: UUID) -> FoodFavorite | None:
        result = await self.session.scalar(
            select(FoodFavorite).where(
                FoodFavorite.user_id == user_id, FoodFavorite.food_id == food_id
            )
        )
        return result
