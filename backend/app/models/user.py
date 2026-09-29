from typing import TYPE_CHECKING

from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(320), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(512), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_superuser: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    sessions: Mapped[list["AuthSession"]] = relationship(back_populates="user")
    health_profile: Mapped["HealthProfile | None"] = relationship(back_populates="user")
    weight_logs: Mapped[list["WeightLog"]] = relationship(back_populates="user")


if TYPE_CHECKING:
    from app.models.auth_session import AuthSession
    from app.models.health_profile import HealthProfile
    from app.models.weight_log import WeightLog
