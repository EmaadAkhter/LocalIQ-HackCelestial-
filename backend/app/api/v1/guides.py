"""Guides API endpoints."""

from fastapi import APIRouter

router = APIRouter()


@router.get("/")
async def list_guides():
    """List all guides."""
    return []


@router.get("/{guide_id}")
async def get_guide(guide_id: str):
    """Get a single guide by ID."""
    return {"id": guide_id}