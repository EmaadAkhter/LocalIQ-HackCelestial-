"""Recommendations API endpoints."""

from fastapi import APIRouter

router = APIRouter()


@router.post("/")
async def get_recommendations():
    """Get personalized recommendations."""
    return []


@router.get("/{recommendation_id}")
async def get_recommendation(recommendation_id: str):
    """Get a single recommendation by ID."""
    return {"id": recommendation_id}