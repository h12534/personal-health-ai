import asyncio
import json
from decimal import Decimal
from pathlib import Path
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import SessionLocal
from app.models.food import FoodAlias, FoodItem
from app.repositories.food_repository import FoodRepository
from app.utils.text import normalize_food_name

SEED_PATH = Path(__file__).parents[1] / "data" / "seed_foods.json"
SOURCE_NAME = "USDA FoodData Central generic foods reference (rounded)"
SOURCE_URL = "https://fdc.nal.usda.gov/"


def _decimal(value: Any) -> Decimal | None:
    return None if value is None else Decimal(str(value))


async def seed_foods(session: AsyncSession) -> tuple[int, int]:
    """Insert or update stable seed IDs; reruns never create duplicates."""
    records: list[dict[str, Any]] = json.loads(SEED_PATH.read_text(encoding="utf-8"))
    repository = FoodRepository(session)
    inserted = 0
    updated = 0
    for record in records:
        source_id = str(record["source_id"])
        food = await repository.by_source("database", source_id)
        aliases = [str(value) for value in record.pop("aliases", [])]
        values = {
            key: _decimal(value)
            if key.endswith("_per_100g") or key == "serving_weight_g"
            else value
            for key, value in record.items()
            if key != "source_id"
        }
        if food is None:
            alias_models = [
                FoodAlias(
                    alias=alias,
                    normalized_alias=normalize_food_name(alias),
                    language="zh-CN",
                )
                for alias in aliases
                if normalize_food_name(alias)
            ]
            food = FoodItem(
                source="database",
                source_id=source_id,
                data_source_name=SOURCE_NAME,
                data_source_url=SOURCE_URL,
                normalized_name=normalize_food_name(str(record["name"])),
                is_custom=False,
                is_active=True,
                aliases=alias_models,
                **values,
            )
            session.add(food)
            inserted += 1
        else:
            for field, value in values.items():
                setattr(food, field, value)
            food.normalized_name = normalize_food_name(food.name)
            food.data_source_name = SOURCE_NAME
            food.data_source_url = SOURCE_URL
            food.is_active = True
            food.deleted_at = None
            updated += 1
            desired = {normalize_food_name(alias): alias for alias in aliases}
            existing = {alias.normalized_alias: alias for alias in food.aliases}
            for normalized, model in existing.items():
                if normalized not in desired:
                    await session.delete(model)
            for normalized, alias in desired.items():
                if normalized in existing:
                    existing[normalized].alias = alias
                elif normalized:
                    food.aliases.append(
                        FoodAlias(alias=alias, normalized_alias=normalized, language="zh-CN")
                    )
    await session.commit()
    return inserted, updated


async def main() -> None:
    async with SessionLocal() as session:
        inserted, updated = await seed_foods(session)
    print(f"Seed complete: inserted={inserted}, updated={updated}")


if __name__ == "__main__":
    asyncio.run(main())
