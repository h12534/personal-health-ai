from fastapi import APIRouter

from app.api.v1.endpoints import (
    auth,
    canteens,
    coach,
    dashboard,
    diet,
    exercises,
    foods,
    health,
    health_ai,
    knowledge,
    labs,
    meal_analyses,
    meals,
    nutrition,
    profile,
    saved_meals,
    training,
    training_coach,
    weight,
    workouts,
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
api_router.include_router(exercises.router, prefix="/exercises", tags=["exercises"])
api_router.include_router(training.router, prefix="/training", tags=["training"])
api_router.include_router(workouts.router, prefix="/workouts", tags=["workouts"])
api_router.include_router(health.activity_router, prefix="/activity", tags=["activity"])
api_router.include_router(health.sleep_router, prefix="/sleep", tags=["sleep"])
api_router.include_router(health.recovery_router, prefix="/recovery", tags=["recovery"])
api_router.include_router(health.health_router, prefix="/health", tags=["health-sync"])
api_router.include_router(knowledge.router, prefix="/knowledge", tags=["knowledge"])
api_router.include_router(labs.router, prefix="/labs", tags=["labs"])
api_router.include_router(training_coach.router, prefix="/ai/training", tags=["ai-training-coach"])
api_router.include_router(health_ai.router, prefix="/ai/health", tags=["ai-health"])
