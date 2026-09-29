from typing import cast
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def count(self) -> int:
        return int(await self.session.scalar(select(func.count(User.id))) or 0)

    async def by_email(self, email: str) -> User | None:
        result = await self.session.scalar(select(User).where(User.email == email.lower()))
        return cast(User | None, result)

    async def by_id(self, user_id: UUID) -> User | None:
        return await self.session.get(User, user_id)

    async def add(self, user: User) -> User:
        self.session.add(user)
        await self.session.flush()
        return user
