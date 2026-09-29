from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.diet_coach import Canteen, CanteenDish, CanteenStall
from app.repositories.diet_coach_repository import DietCoachRepository
from app.repositories.meal_repository import MealRepository
from app.schemas.diet_coach import (
    CanteenDetailRead,
    CanteenRead,
    CanteenWrite,
    DishRead,
    DishRecommendationRead,
    DishWrite,
    MealTargetRange,
    StallDetailRead,
    StallRead,
    StallWrite,
)
from app.utils.text import normalize_food_name


class CanteenService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = DietCoachRepository(session)
        self.meals = MealRepository(session)

    async def list_all(self, user_id: UUID) -> list[Canteen]:
        return await self.repo.canteens(user_id)

    async def list_details(self, user_id: UUID) -> list[CanteenDetailRead]:
        values = await self.list_all(user_id)
        return [
            CanteenDetailRead(
                **CanteenRead.model_validate(canteen).model_dump(),
                stalls=[
                    StallDetailRead(
                        **StallRead.model_validate(stall).model_dump(),
                        dishes=[
                            DishRead.model_validate(dish)
                            for dish in stall.dishes
                            if dish.is_available
                        ],
                    )
                    for stall in canteen.stalls
                    if stall.is_active
                ],
            )
            for canteen in values
        ]

    async def create(self, user_id: UUID, payload: CanteenWrite) -> Canteen:
        value = Canteen(user_id=user_id, **payload.model_dump())
        self.session.add(value)
        await self.session.commit()
        await self.session.refresh(value)
        return value

    async def add_stall(self, user_id: UUID, canteen_id: UUID, payload: StallWrite) -> CanteenStall:
        if await self.repo.canteen(user_id, canteen_id) is None:
            raise AppError("canteen_not_found", "Canteen was not found.", 404)
        value = CanteenStall(canteen_id=canteen_id, **payload.model_dump())
        self.session.add(value)
        await self.session.commit()
        await self.session.refresh(value)
        return value

    async def add_dish(self, user_id: UUID, stall_id: UUID, payload: DishWrite) -> CanteenDish:
        if await self.repo.stall(user_id, stall_id) is None:
            raise AppError("stall_not_found", "Canteen stall was not found.", 404)
        value = CanteenDish(stall_id=stall_id, **payload.model_dump())
        self.session.add(value)
        await self.session.commit()
        await self.session.refresh(value)
        return value

    async def delete_canteen(self, user_id: UUID, canteen_id: UUID) -> None:
        value = await self.repo.canteen(user_id, canteen_id)
        if value is None:
            raise AppError("canteen_not_found", "Canteen was not found.", 404)
        value.is_active = False
        await self.session.commit()

    async def delete_stall(self, user_id: UUID, stall_id: UUID) -> None:
        value = await self.repo.stall(user_id, stall_id)
        if value is None:
            raise AppError("stall_not_found", "Canteen stall was not found.", 404)
        value.is_active = False
        await self.session.commit()

    async def delete_dish(self, user_id: UUID, dish_id: UUID) -> None:
        value = await self.repo.dish(user_id, dish_id)
        if value is None:
            raise AppError("dish_not_found", "Canteen dish was not found.", 404)
        value.is_available = False
        await self.session.commit()

    async def update_canteen(
        self, user_id: UUID, canteen_id: UUID, payload: CanteenWrite
    ) -> Canteen:
        value = await self.repo.canteen(user_id, canteen_id)
        if value is None:
            raise AppError("canteen_not_found", "Canteen was not found.", 404)
        for field, field_value in payload.model_dump().items():
            setattr(value, field, field_value)
        await self.session.commit()
        await self.session.refresh(value)
        return value

    async def update_stall(
        self, user_id: UUID, stall_id: UUID, payload: StallWrite
    ) -> CanteenStall:
        value = await self.repo.stall(user_id, stall_id)
        if value is None:
            raise AppError("stall_not_found", "Canteen stall was not found.", 404)
        for field, field_value in payload.model_dump().items():
            setattr(value, field, field_value)
        await self.session.commit()
        await self.session.refresh(value)
        return value

    async def update_dish(self, user_id: UUID, dish_id: UUID, payload: DishWrite) -> CanteenDish:
        value = await self.repo.dish(user_id, dish_id)
        if value is None:
            raise AppError("dish_not_found", "Canteen dish was not found.", 404)
        for field, field_value in payload.model_dump().items():
            setattr(value, field, field_value)
        await self.session.commit()
        await self.session.refresh(value)
        return value

    async def learn_from_meal(
        self, user_id: UUID, stall_id: UUID, meal_id: UUID
    ) -> list[CanteenDish]:
        stall = await self.repo.stall(user_id, stall_id)
        meal = await self.meals.by_id(user_id, meal_id)
        if stall is None:
            raise AppError("stall_not_found", "Canteen stall was not found.", 404)
        if meal is None:
            raise AppError("meal_not_found", "Meal was not found.", 404)
        existing = {normalize_food_name(item.name): item for item in stall.dishes}
        result: list[CanteenDish] = []
        for item in meal.items:
            key = normalize_food_name(item.food_name_snapshot)
            dish = existing.get(key)
            if dish is None:
                dish = CanteenDish(
                    stall_id=stall_id,
                    food_item_id=item.food_id,
                    name=item.food_name_snapshot,
                    calories=item.calories,
                    protein_g=item.protein,
                    carbs_g=item.carbs,
                    fat_g=item.fat,
                    fiber_g=item.fiber,
                    average_weight_g=item.weight_g,
                    confidence=1,
                    times_logged=1,
                    last_seen=meal.eaten_at,
                    source="confirmed_meal",
                )
                self.session.add(dish)
                existing[key] = dish
            else:
                samples = max(1, dish.times_logged)
                dish.average_weight_g = (
                    (dish.average_weight_g or item.weight_g) * samples + item.weight_g
                ) / (samples + 1)
                dish.times_logged = samples + 1
                dish.last_seen = meal.eaten_at
                dish.food_item_id = dish.food_item_id or item.food_id
            result.append(dish)
        await self.session.commit()
        for dish in result:
            await self.session.refresh(dish)
        return result

    async def recommend(
        self, user_id: UUID, target: MealTargetRange, canteen_id: UUID | None = None
    ) -> list[DishRecommendationRead]:
        canteens = await self.repo.canteens(user_id)
        if canteen_id is not None:
            canteens = [value for value in canteens if value.id == canteen_id]
        dishes = [
            dish
            for canteen in canteens
            for stall in canteen.stalls
            for dish in stall.dishes
            if dish.is_available
        ]
        center = Decimal(target.calories_min + target.calories_max) / 2
        protein_center = (target.protein_min_g + target.protein_max_g) / 2
        ranked: list[tuple[Decimal, CanteenDish, list[str]]] = []
        for dish in dishes:
            calorie_fit = max(
                Decimal("0"), Decimal("1") - abs(dish.calories - center) / max(center, Decimal("1"))
            )
            protein_fit = min(Decimal("1"), dish.protein_g / max(protein_center, Decimal("1")))
            score = calorie_fit * Decimal("0.55") + protein_fit * Decimal("0.45")
            reasons = []
            if target.calories_min <= dish.calories <= target.calories_max:
                reasons.append("热量落在下一餐建议范围内")
            if dish.protein_g >= target.protein_min_g:
                reasons.append("蛋白质达到本餐建议下限")
            if not reasons:
                reasons.append("在当前可用菜品中相对接近目标")
            ranked.append((score, dish, reasons))
        ranked.sort(key=lambda value: (value[0], value[1].protein_g), reverse=True)
        return [
            DishRecommendationRead(
                dish=DishRead.model_validate(dish),
                match_score=(score * 100).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP),
                reasons=reasons,
            )
            for score, dish, reasons in ranked[:10]
        ]
