from fastapi import APIRouter

from app.api.v1.endpoints import (
    auth,
    dashboard,
    foods,
    meal_analyses,
    meals,
    nutrition,
    profile,
    weight,
)

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(profile.router, prefix="/profile", tags=["profile"])
api_router.include_router(weight.router, prefix="/weight", tags=["weight"])
api_router.include_router(foods.router, prefix="/foods", tags=["foods"])
api_router.include_router(meals.router, prefix="/meals", tags=["meals"])
api_router.include_router(meal_analyses.router, tags=["meal-analysis"])
api_router.include_router(nutrition.router, prefix="/nutrition", tags=["nutrition"])
api_router.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])
