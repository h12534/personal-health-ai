"""Release candidate hardening for push-device environment isolation."""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0008_release_candidate"
down_revision: str | None = "0007_phase7_supervision"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_index("ix_exercise_library_normalized_name", table_name="exercise_library")
    op.create_index(
        "ix_exercise_library_normalized_name",
        "exercise_library",
        ["normalized_name"],
        unique=True,
    )
    with op.batch_alter_table("push_devices") as batch:
        batch.add_column(
            sa.Column(
                "environment",
                sa.String(length=24),
                nullable=False,
                server_default="dev",
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("push_devices") as batch:
        batch.drop_column("environment")
    op.drop_index("ix_exercise_library_normalized_name", table_name="exercise_library")
    op.create_index(
        "ix_exercise_library_normalized_name",
        "exercise_library",
        ["normalized_name"],
        unique=False,
    )
