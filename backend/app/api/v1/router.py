from fastapi import APIRouter

from app.api.v1.endpoints import (
    auth,
    canteens,
    coach,
    dashboard,
    diet,
    foods,
    meal_analyses,
    meals,
    nutrition,
    profile,
    saved_meals,
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
api_router.include_router(diet.router, prefix="/diet", tags=["diet-coach"])
api_router.include_router(canteens.router, prefix="/canteens", tags=["canteens"])
api_router.include_router(saved_meals.router, prefix="/saved-meals", tags=["saved-meals"])
api_router.include_router(coach.router, prefix="/ai/coach", tags=["ai-coach"])
