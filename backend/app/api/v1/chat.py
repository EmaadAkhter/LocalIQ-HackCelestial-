"""Chat API endpoints: context-scoped AI guide."""

from fastapi import APIRouter

from app.schemas import ChatRequest, ChatResponse
from app.services.guide import answer

router = APIRouter()


@router.post("/", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    """Answer a traveller's question about a specific experience."""
    return await answer(request)
