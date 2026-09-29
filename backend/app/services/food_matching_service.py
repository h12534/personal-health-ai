from dataclasses import dataclass
from difflib import SequenceMatcher
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.food import FoodItem
from app.models.meal_analysis import PersonalFoodMemory
from app.repositories.food_repository import FoodRepository
from app.utils.text import normalize_food_name

COOKING_PREFIXES = (
    "清炒",
    "爆炒",
    "红烧",
    "香煎",
    "油炸",
    "烤",
    "蒸",
    "炒",
    "煎",
    "炸",
    "炖",
    "煮",
)


@dataclass(frozen=True, slots=True)
class FoodMatch:
    food: FoodItem | None
    match_type: str
    confidence: float


class FoodMatchingService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.foods = FoodRepository(session)

    @staticmethod
    def _names(name: str, aliases: list[str]) -> list[str]:
        normalized = [normalize_food_name(value) for value in [name, *aliases] if value.strip()]
        expanded = list(normalized)
        for value in normalized:
            for prefix in COOKING_PREFIXES:
                if value.startswith(prefix) and len(value) > len(prefix):
                    expanded.append(value[len(prefix) :])
        return list(dict.fromkeys(expanded))

    async def match(
        self,
        user_id: UUID,
        detected_name: str,
        aliases: list[str] | None = None,
        location_context: str | None = None,
    ) -> FoodMatch:
        names = self._names(detected_name, aliases or [])
        location = location_context or "unspecified"
        memory = await self.session.scalar(
            select(PersonalFoodMemory)
            .options(selectinload(PersonalFoodMemory.confirmed_food))
            .where(
                PersonalFoodMemory.user_id == user_id,
                PersonalFoodMemory.normalized_detected_label.in_(names),
                PersonalFoodMemory.location_context.in_([location, "unspecified"]),
            )
            .order_by(PersonalFoodMemory.sample_count.desc())
            .limit(1)
        )
        if memory is not None:
            return FoodMatch(memory.confirmed_food, "personal_memory", float(memory.confidence))

        foods = await self.foods.all_for_matching(user_id)
        for custom_only, match_type in ((True, "custom_exact"), (False, "exact")):
            for food in foods:
                if food.is_custom != custom_only:
                    continue
                if food.normalized_name in names:
                    return FoodMatch(food, match_type, 1.0)
        for food in foods:
            if any(alias.normalized_alias in names for alias in food.aliases):
                return FoodMatch(food, "alias", 0.95)

        best_food: FoodItem | None = None
        best_score = 0.0
        for food in foods:
            candidates = [food.normalized_name, *(a.normalized_alias for a in food.aliases)]
            for left in names:
                for right in candidates:
                    containment = 0.86 if left in right or right in left else 0.0
                    score = max(containment, SequenceMatcher(None, left, right).ratio())
                    if score > best_score:
                        best_food, best_score = food, score
        if best_food is not None and best_score >= 0.62:
            return FoodMatch(best_food, "fuzzy", min(best_score, 0.89))
        return FoodMatch(None, "unmatched", 0.0)
