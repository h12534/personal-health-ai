import asyncio
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from time import perf_counter

import structlog
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from redis.asyncio import Redis
from sqlalchemy import text

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.errors import AppError
from app.db.session import SessionLocal

logger = structlog.get_logger()
settings = get_settings()


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    logger.info("application_started", environment=settings.app_env)
    yield
    logger.info("application_stopped")


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    docs_url="/docs" if not settings.is_production else None,
    redoc_url=None,
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-ID"],
)
app.include_router(api_router, prefix="/api/v1")


@app.middleware("http")
async def request_context(request: Request, call_next):  # type: ignore[no-untyped-def]
    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))[:128]
    request.state.request_id = request_id
    started = perf_counter()
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    logger.info(
        "request_completed",
        request_id=request_id,
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
        duration_ms=round((perf_counter() - started) * 1000, 2),
    )
    return response


@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {"code": exc.code, "message": exc.message, "details": exc.details},
            "request_id": getattr(request.state, "request_id", "unknown"),
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    safe_errors = [
        {"type": error["type"], "loc": error["loc"], "msg": error["msg"]} for error in exc.errors()
    ]
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "validation_error",
                "message": "Request validation failed.",
                "details": safe_errors,
            },
            "request_id": getattr(request.state, "request_id", "unknown"),
        },
    )


@app.get("/health", tags=["system"])
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/live", tags=["system"])
async def health_live() -> dict[str, str]:
    return {"status": "live"}


@app.get("/ready", tags=["system"])
async def ready() -> JSONResponse:
    return await _readiness()


@app.get("/health/ready", tags=["system"])
async def health_ready() -> JSONResponse:
    return await _readiness()


async def _readiness() -> JSONResponse:
    checks: dict[str, str] = {}
    try:
        async with SessionLocal() as session:
            await session.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception:
        logger.exception("readiness_database_failed")
        checks["database"] = "failed"
    redis: Redis | None = None
    try:
        redis = Redis.from_url(
            settings.redis_url,
            socket_connect_timeout=1,
            socket_timeout=1,
            decode_responses=True,
        )
        await redis.ping()
        checks["redis"] = "ok"
    except Exception:
        logger.exception("readiness_redis_failed")
        checks["redis"] = "failed"
    finally:
        if redis is not None:
            await redis.aclose()
    storage_path = Path(settings.upload_dir)
    storage_ready = await asyncio.to_thread(lambda: storage_path.exists() and storage_path.is_dir())
    checks["storage"] = "ok" if storage_ready else "failed"
    is_ready = all(value == "ok" for value in checks.values())
    return JSONResponse(
        {"status": "ready" if is_ready else "not_ready", "checks": checks},
        status_code=200 if is_ready else 503,
    )
