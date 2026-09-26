"""Discovery API endpoints for finding hidden gems via SearXNG."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field
from sqlmodel import Session

from app.database import get_session
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.services.discovery import discover_activities

router = APIRouter()


class DiscoveryRequest(BaseModel):
    query: str = Field(..., min_length=2, max_length=200)
    area: str | None = Field(default=None, max_length=100)
    max_results: int = Field(default=10, ge=1, le=20)
    store: bool = Field(default=True)


class DiscoveryResponse(BaseModel):
    candidates: list[dict]
    query: str
    area: str | None


@router.post("/discover", summary="Discover activities via SearXNG")
@limiter.limit(PUBLIC_LIMIT)
async def discover(
    request: Request,
    response: Response,
    payload: DiscoveryRequest,
    session: Session = Depends(get_session),
):
    """Search the web for activity candidates and optionally store them.

    Requires a self-hosted SearXNG instance (``SEARXNG_URL``). When disabled or
    unreachable, returns an empty candidate list.
    """
    candidates = await discover_activities(
        payload.query,
        area=payload.area,
        max_results=payload.max_results,
        store=payload.store,
    )
    return DiscoveryResponse(
        candidates=candidates,
        query=payload.query,
        area=payload.area,
    )
