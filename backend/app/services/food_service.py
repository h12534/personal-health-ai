from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.food import FoodAlias, FoodFavorite, FoodItem
from app.repositories.food_repository import FoodRepository
from app.schemas.food import FavoriteRead, FoodCreate, FoodRead, FoodUpdate
from app.utils.text import normalize_food_name


class FoodService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repository = FoodRepository(session)

    async def get(self, user_id: UUID, food_id: UUID) -> FoodRead:
        food = await self.repository.by_id(user_id, food_id)
        if food is None:
            raise AppError("food_not_found", "Food was not found.", 404)
        favorites = await self.repository.favorite_ids(user_id, [food.id])
        return self._read(food, food.id in favorites)

    async def search(
        self, user_id: UUID, query: str = "", category: str | None = None, limit: int = 30
    ) -> list[FoodRead]:
        foods = await self.repository.search(
            user_id, normalize_food_name(query), category=category, limit=limit
        )
        favorite_ids = await self.repository.favorite_ids(user_id, [food.id for food in foods])
        return [self._read(food, food.id in favorite_ids) for food in foods]

    async def create(self, user_id: UUID, payload: FoodCreate) -> FoodRead:
        values = payload.model_dump(exclude={"aliases"})
        food = FoodItem(
            owner_user_id=user_id,
            normalized_name=normalize_food_name(payload.name),
            source="user",
            is_custom=True,
            aliases=self._build_aliases(payload.aliases),
            **values,
        )
        self.session.add(food)
        await self.session.commit()
        await self.session.refresh(food, attribute_names=["aliases"])
        return self._read(food, False)

    async def update(self, user_id: UUID, food_id: UUID, payload: FoodUpdate) -> FoodRead:
        food = await self.repository.custom_by_id(user_id, food_id)
        if food is None:
            raise AppError("custom_food_not_found", "Editable custom food was not found.", 404)
        values = payload.model_dump(exclude_unset=True, exclude={"aliases"})
        for field, value in values.items():
            setattr(food, field, value)
        if payload.name is not None:
            food.normalized_name = normalize_food_name(payload.name)
        if "aliases" in payload.model_fields_set:
            await self._sync_aliases(food, payload.aliases or [])
        await self.session.commit()
        await self.session.refresh(food, attribute_names=["aliases"])
        favorites = await self.repository.favorite_ids(user_id, [food.id])
        return self._read(food, food.id in favorites)

    async def delete(self, user_id: UUID, food_id: UUID) -> None:
        food = await self.repository.custom_by_id(user_id, food_id)
        if food is None:
            raise AppError("custom_food_not_found", "Editable custom food was not found.", 404)
        food.deleted_at = datetime.now(UTC)
        food.is_active = False
        await self.session.commit()

    async def add_favorite(self, user_id: UUID, food_id: UUID) -> FoodRead:
        food = await self.repository.by_id(user_id, food_id)
        if food is None:
            raise AppError("food_not_found", "Food was not found.", 404)
        if await self.repository.favorite(user_id, food_id) is None:
            self.session.add(FoodFavorite(user_id=user_id, food_id=food_id))
            await self.session.commit()
        return self._read(food, True)

    async def remove_favorite(self, user_id: UUID, food_id: UUID) -> None:
        favorite = await self.repository.favorite(user_id, food_id)
        if favorite is not None:
            await self.session.delete(favorite)
            await self.session.commit()

    async def favorites(self, user_id: UUID) -> list[FavoriteRead]:
        rows = await self.repository.favorites(user_id)
        return [FavoriteRead(food=self._read(food, True), favorited_at=at) for food, at in rows]

    async def recent(self, user_id: UUID, limit: int = 20) -> list[FoodRead]:
        foods = await self.repository.recent(user_id, limit)
        favorite_ids = await self.repository.favorite_ids(user_id, [food.id for food in foods])
        return [self._read(food, food.id in favorite_ids) for food in foods]

    async def _sync_aliases(self, food: FoodItem, aliases: list[str]) -> None:
        desired = {alias.normalized_alias: alias for alias in self._build_aliases(aliases)}
        existing = {alias.normalized_alias: alias for alias in food.aliases}
        for normalized, model in existing.items():
            if normalized not in desired:
                await self.session.delete(model)
        for normalized, model in desired.items():
            if normalized in existing:
                existing[normalized].alias = model.alias
            else:
                food.aliases.append(model)

    @staticmethod
    def _build_aliases(aliases: list[str]) -> list[FoodAlias]:
        built: list[FoodAlias] = []
        seen: set[str] = set()
        for alias in aliases:
            clean = alias.strip()
            normalized = normalize_food_name(clean)
            if clean and normalized and normalized not in seen:
                built.append(FoodAlias(alias=clean, normalized_alias=normalized, language="zh-CN"))
                seen.add(normalized)
        return built

    @staticmethod
    def _read(food: FoodItem, is_favorite: bool) -> FoodRead:
        values = {
            column.name: getattr(food, column.name)
            for column in FoodItem.__table__.columns
            if column.name not in {"owner_user_id", "normalized_name", "deleted_at", "is_active"}
        }
        return FoodRead(
            **values,
            aliases=[alias.alias for alias in food.aliases],
            is_favorite=is_favorite,
        )
