"""Chat API endpoints."""

from fastapi import APIRouter

router = APIRouter()


@router.post("/")
async def chat():
    """Handle chat messages."""
    return {}