from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.diet_coach import SavedMeal, SavedMealItem
from app.models.meal import MealItem, MealLog
from app.repositories.diet_coach_repository import DietCoachRepository
from app.repositories.meal_repository import MealRepository
from app.schemas.diet_coach import SavedMealLogWrite, SavedMealWrite


class SavedMealService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = DietCoachRepository(session)
        self.meals = MealRepository(session)

    async def list(self, user_id: UUID) -> list[SavedMeal]:
        return await self.repo.saved_meals(user_id)

    async def create(self, user_id: UUID, payload: SavedMealWrite) -> SavedMeal:
        saved = SavedMeal(
            user_id=user_id,
            name=payload.name,
            meal_type=payload.meal_type,
            note=payload.note,
            items=[
                SavedMealItem(
                    food_id=item.food_id,
                    food_name_snapshot=item.food_name,
                    amount=item.amount,
                    amount_unit=item.amount_unit,
                    weight_g=item.weight_g,
                    calories=item.calories,
                    protein=item.protein,
                    carbs=item.carbs,
                    fat=item.fat,
                    fiber=item.fiber,
                )
                for item in payload.items
            ],
        )
        self.session.add(saved)
        await self.session.commit()
        await self.session.refresh(saved, attribute_names=["items"])
        return saved

    async def delete(self, user_id: UUID, saved_meal_id: UUID) -> None:
        saved = await self.repo.saved_meal(user_id, saved_meal_id)
        if saved is None:
            raise AppError("saved_meal_not_found", "Saved meal was not found.", 404)
        saved.deleted_at = datetime.now(UTC)
        await self.session.commit()

    async def log(self, user_id: UUID, saved_meal_id: UUID, payload: SavedMealLogWrite) -> MealLog:
        existing = await self.meals.by_idempotency(user_id, payload.idempotency_key)
        if existing is not None:
            return existing
        saved = await self.repo.saved_meal(user_id, saved_meal_id)
        if saved is None:
            raise AppError("saved_meal_not_found", "Saved meal was not found.", 404)
        items = [
            MealItem(
                food_id=item.food_id,
                food_name_snapshot=item.food_name_snapshot,
                amount=item.amount,
                amount_unit=item.amount_unit,
                weight_g=item.weight_g,
                calories=item.calories,
                protein=item.protein,
                carbs=item.carbs,
                fat=item.fat,
                fiber=item.fiber,
                nutrition_source=f"saved_meal:{saved.id}",
            )
            for item in saved.items
        ]
        meal = MealLog(
            user_id=user_id,
            meal_type=payload.meal_type or saved.meal_type,
            eaten_at=payload.eaten_at.astimezone(UTC),
            note=saved.note,
            source="saved_meal",
            idempotency_key=payload.idempotency_key,
            items=items,
            total_calories=sum((item.calories for item in items), Decimal("0")),
            total_protein=sum((item.protein for item in items), Decimal("0")),
            total_carbs=sum((item.carbs for item in items), Decimal("0")),
            total_fat=sum((item.fat for item in items), Decimal("0")),
            total_fiber=sum((item.fiber for item in items), Decimal("0")),
        )
        self.session.add(meal)
        await self.session.commit()
        await self.session.refresh(meal, attribute_names=["items"])
        return meal
