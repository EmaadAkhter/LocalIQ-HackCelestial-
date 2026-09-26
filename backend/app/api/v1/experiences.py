"""Experiences API endpoints."""

from fastapi import APIRouter

router = APIRouter()


@router.get("/")
async def list_experiences():
    """List all experiences."""
    return []


@router.get("/{experience_id}")
async def get_experience(experience_id: str):
    """Get a single experience by ID."""
    return {"id": experience_id}