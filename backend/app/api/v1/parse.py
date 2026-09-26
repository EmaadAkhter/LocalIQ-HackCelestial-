"""Parse API endpoints."""

from fastapi import APIRouter

router = APIRouter()


@router.post("/")
async def parse_input():
    """Parse natural language input."""
    return {}