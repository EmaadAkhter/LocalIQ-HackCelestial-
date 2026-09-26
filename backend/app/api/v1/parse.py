"""Parse API endpoints: natural language -> structured constraints."""

from fastapi import APIRouter

from app.schemas import ParseRequest, ParseResponse
from app.services.parser import parse_constraints

router = APIRouter()


@router.post("/", response_model=ParseResponse)
async def parse_input(request: ParseRequest) -> ParseResponse:
    """Extract structured constraints from a free-text request."""
    return await parse_constraints(request.text)
