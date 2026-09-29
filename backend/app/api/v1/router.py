from fastapi import APIRouter

from app.api.v1.endpoints import auth, dashboard, profile, weight

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(profile.router, prefix="/profile", tags=["profile"])
api_router.include_router(weight.router, prefix="/weight", tags=["weight"])
api_router.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])
