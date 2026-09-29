.PHONY: install test lint format typecheck migrate run

install:
	python -m pip install -e ".[dev]"

test:
	pytest

lint:
	ruff check .

format:
	ruff format .

typecheck:
	mypy app

migrate:
	alembic upgrade head

run:
	uvicorn app.main:app --reload

