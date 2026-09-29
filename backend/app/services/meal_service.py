from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.food import FoodItem
from app.models.meal import MealItem, MealLog
from app.repositories.food_repository import FoodRepository
from app.repositories.meal_repository import MealRepository
from app.repositories.profile_repository import ProfileRepository
from app.schemas.meal import (
    MealCreate,
    MealItemRead,
    MealItemUpdate,
    MealItemWrite,
    MealRead,
    MealUpdate,
)
from app.services.nutrition_calculator import NutritionCalculator, quantize_nutrition

logger = structlog.get_logger()
ZERO = Decimal("0")


class MealService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.meals = MealRepository(session)
        self.foods = FoodRepository(session)
        self.profiles = ProfileRepository(session)

    async def create(
        self, user_id: UUID, payload: MealCreate, idempotency_key: str | None
    ) -> MealRead:
        key = self._clean_key(idempotency_key)
        if key:
            existing = await self.meals.by_idempotency(user_id, key)
            if existing is not None:
                return self._read(existing)
        meal = MealLog(
            user_id=user_id,
            meal_type=payload.meal_type,
            eaten_at=payload.eaten_at.astimezone(UTC),
            note=payload.note,
            source=payload.source,
            idempotency_key=key,
            items=[],
        )
        self.session.add(meal)
        await self.session.commit()
        await self.session.refresh(meal, attribute_names=["items"])
        logger.info(
            "meal_created", meal_id=str(meal.id), user_id=str(user_id), meal_type=meal.meal_type
        )
        return self._read(meal)

    async def list(
        self, user_id: UUID, date_from: date | None = None, date_to: date | None = None
    ) -> list[MealRead]:
        today = datetime.now(await self._timezone(user_id)).date()
        start_date = date_from or today
        end_date = date_to or start_date
        if end_date < start_date or (end_date - start_date).days > 366:
            raise AppError("invalid_date_range", "Meal date range is invalid or too large.", 422)
        timezone = await self._timezone(user_id)
        start = datetime.combine(start_date, time.min, timezone).astimezone(UTC)
        end = datetime.combine(end_date + timedelta(days=1), time.min, timezone).astimezone(UTC)
        return [self._read(meal) for meal in await self.meals.list_for_user(user_id, start, end)]

    async def get(self, user_id: UUID, meal_id: UUID) -> MealRead:
        return self._read(await self._owned(user_id, meal_id))

    async def update(self, user_id: UUID, meal_id: UUID, payload: MealUpdate) -> MealRead:
        meal = await self._owned(user_id, meal_id)
        values = payload.model_dump(exclude_unset=True)
        if values.get("eaten_at") is not None:
            values["eaten_at"] = values["eaten_at"].astimezone(UTC)
        for field, value in values.items():
            setattr(meal, field, value)
        await self.session.commit()
        logger.info("meal_updated", meal_id=str(meal.id), user_id=str(user_id))
        return self._read(meal)

    async def delete(self, user_id: UUID, meal_id: UUID) -> None:
        meal = await self._owned(user_id, meal_id)
        deleted_at = datetime.now(UTC)
        meal.deleted_at = deleted_at
        for item in meal.items:
            item.deleted_at = deleted_at
        await self.session.commit()
        logger.info("meal_deleted", meal_id=str(meal.id), user_id=str(user_id))

    async def add_item(
        self,
        user_id: UUID,
        meal_id: UUID,
        payload: MealItemWrite,
        idempotency_key: str | None,
    ) -> MealRead:
        meal = await self._owned(user_id, meal_id)
        key = self._clean_key(idempotency_key)
        if key and await self.meals.item_by_idempotency(meal_id, key) is not None:
            return self._read(meal)
        food = await self._visible_food(user_id, payload.food_id)
        item = self._make_item(food, payload.amount, payload.amount_unit, key)
        meal.items.append(item)
        self._recalculate(meal)
        await self.session.commit()
        return self._read(meal)

    async def update_item(
        self, user_id: UUID, meal_id: UUID, item_id: UUID, payload: MealItemUpdate
    ) -> MealRead:
        meal = await self._owned(user_id, meal_id)
        item = await self.meals.item_by_id(meal_id, item_id)
        if item is None:
            raise AppError("meal_item_not_found", "Meal item was not found.", 404)
        food_id = payload.food_id or item.food_id
        if food_id is None:
            raise AppError("food_not_found", "Food was not found.", 404)
        food = await self._visible_food(user_id, food_id)
        amount = payload.amount if payload.amount is not None else item.amount
        unit = payload.amount_unit or item.amount_unit
        values = NutritionCalculator.calculate(food, amount, unit)
        item.food_id = food.id
        item.food_name_snapshot = food.name
        item.amount = amount
        item.amount_unit = unit
        item.weight_g = values.weight_g
        item.calories = values.calories
        item.protein = values.protein
        item.carbs = values.carbs
        item.fat = values.fat
        item.fiber = values.fiber
        item.nutrition_source = f"{food.source}:{food.source_id or food.id}"
        self._recalculate(meal)
        await self.session.commit()
        return self._read(meal)

    async def delete_item(self, user_id: UUID, meal_id: UUID, item_id: UUID) -> MealRead:
        meal = await self._owned(user_id, meal_id)
        item = await self.meals.item_by_id(meal_id, item_id)
        if item is None:
            raise AppError("meal_item_not_found", "Meal item was not found.", 404)
        item.deleted_at = datetime.now(UTC)
        self._recalculate(meal)
        await self.session.commit()
        return self._read(meal)

    async def _owned(self, user_id: UUID, meal_id: UUID) -> MealLog:
        meal = await self.meals.by_id(user_id, meal_id)
        if meal is None:
            raise AppError("meal_not_found", "Meal was not found.", 404)
        return meal

    async def _visible_food(self, user_id: UUID, food_id: UUID) -> FoodItem:
        food = await self.foods.by_id(user_id, food_id)
        if food is None:
            raise AppError("food_not_found", "Food was not found.", 404)
        return food

    async def _timezone(self, user_id: UUID) -> ZoneInfo:
        profile = await self.profiles.by_user(user_id)
        name = profile.timezone if profile else "Asia/Shanghai"
        try:
            return ZoneInfo(name)
        except ZoneInfoNotFoundError:
            return ZoneInfo("UTC")

    @staticmethod
    def _make_item(food: FoodItem, amount: Decimal, unit: str, key: str | None) -> MealItem:
        values = NutritionCalculator.calculate(food, amount, unit)
        return MealItem(
            food_id=food.id,
            food_name_snapshot=food.name,
            amount=amount,
            amount_unit=unit,
            weight_g=values.weight_g,
            calories=values.calories,
            protein=values.protein,
            carbs=values.carbs,
            fat=values.fat,
            fiber=values.fiber,
            nutrition_source=f"{food.source}:{food.source_id or food.id}",
            idempotency_key=key,
        )

    @staticmethod
    def _recalculate(meal: MealLog) -> None:
        active = [item for item in meal.items if item.deleted_at is None]
        meal.total_calories = quantize_nutrition(sum((x.calories for x in active), ZERO))
        meal.total_protein = quantize_nutrition(sum((x.protein for x in active), ZERO))
        meal.total_carbs = quantize_nutrition(sum((x.carbs for x in active), ZERO))
        meal.total_fat = quantize_nutrition(sum((x.fat for x in active), ZERO))
        meal.total_fiber = quantize_nutrition(sum((x.fiber for x in active), ZERO))

    @staticmethod
    def _read(meal: MealLog) -> MealRead:
        eaten_at = meal.eaten_at
        if eaten_at.tzinfo is None:
            eaten_at = eaten_at.replace(tzinfo=UTC)
        return MealRead(
            id=meal.id,
            meal_type=meal.meal_type,
            eaten_at=eaten_at,
            note=meal.note,
            source=meal.source,
            total_calories=meal.total_calories,
            total_protein=meal.total_protein,
            total_carbs=meal.total_carbs,
            total_fat=meal.total_fat,
            total_fiber=meal.total_fiber,
            items=[
                MealItemRead.model_validate(item) for item in meal.items if item.deleted_at is None
            ],
            created_at=meal.created_at,
            updated_at=meal.updated_at,
        )

    @staticmethod
    def _clean_key(value: str | None) -> str | None:
        clean = value.strip() if value else None
        return clean or None
