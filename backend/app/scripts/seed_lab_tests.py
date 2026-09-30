import asyncio
import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import SessionLocal
from app.models.health_knowledge import LabTestDictionary

DATA_FILE = Path(__file__).parents[1] / "data" / "seed_lab_tests.json"


async def seed_lab_tests(session: AsyncSession) -> tuple[int, int]:
    values = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    existing = {
        item.canonical_name: item
        for item in (await session.scalars(select(LabTestDictionary))).all()
    }
    created = 0
    updated = 0
    for payload in values:
        item = existing.get(payload["canonical_name"])
        if item is None:
            session.add(LabTestDictionary(**payload, active=True))
            created += 1
        else:
            for field, value in payload.items():
                setattr(item, field, value)
            item.active = True
            updated += 1
    await session.commit()
    return created, updated


async def _main() -> None:
    async with SessionLocal() as session:
        created, updated = await seed_lab_tests(session)
    print(f"created={created} updated={updated}")


if __name__ == "__main__":
    asyncio.run(_main())
