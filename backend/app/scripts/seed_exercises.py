import asyncio
import json
from pathlib import Path
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import SessionLocal
from app.models.training import Exercise

SEED_PATH = Path(__file__).parents[1] / "data" / "seed_exercises.json"


async def seed_exercises(session: AsyncSession) -> tuple[int, int]:
    """Upsert the curated exercise library by stable normalized name."""
    records: list[dict[str, Any]] = json.loads(SEED_PATH.read_text(encoding="utf-8"))
    inserted = 0
    updated = 0
    for record in records:
        normalized = str(record["normalized_name"]).strip().lower()
        exercise = await session.scalar(
            select(Exercise).where(Exercise.normalized_name == normalized)
        )
        values = dict(record)
        values["normalized_name"] = normalized
        values.setdefault("video_url", None)
        values.setdefault("image_url", None)
        values["active"] = True
        if exercise is None:
            session.add(Exercise(**values))
            inserted += 1
        else:
            for field, value in values.items():
                setattr(exercise, field, value)
            updated += 1
    await session.commit()
    return inserted, updated


async def main() -> None:
    async with SessionLocal() as session:
        inserted, updated = await seed_exercises(session)
    print(f"Exercise seed complete: inserted={inserted}, updated={updated}")


if __name__ == "__main__":
    asyncio.run(main())
