"""LocalIQ Companion / guide agent endpoints (PRD 4.7 + 4.10)."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlmodel import Session

from app.database import get_session
from app.models import ConversationSession, Experience, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.services import companion, graphs, taste
from app.services.auth import get_current_user_optional
from app.services.recommender import resolve_location
from app.services.weather import fetch_weather, neutral_weather

logger = logging.getLogger(__name__)
router = APIRouter()


class AgentChatRequest(BaseModel):
    session_id: int | None = None
    message: str = Field(min_length=1, max_length=2000)
    language: str | None = Field(default=None, max_length=8)
    lat: float | None = None
    lng: float | None = None


class AgentRecommendation(BaseModel):
    id: int
    name: str
    category: str
    avg_cost: int
    area: str | None = None
    why: list[str] = Field(default_factory=list)
    score: float
    distance_km: float
    travel_time_min: int


class AgentChatResponse(BaseModel):
    session_id: int
    reply: str
    mode: str
    language: str
    constraints: dict[str, Any]
    recommendations: list[AgentRecommendation] = Field(default_factory=list)


class GuideRequest(BaseModel):
    experience_id: int
    language: str | None = Field(default=None, max_length=8)


class GuideResponse(BaseModel):
    experience_id: int
    name: str
    tips: list[str]


class SessionResponse(BaseModel):
    session_id: int
    language: str
    messages: list[dict[str, Any]]
    constraints: dict[str, Any]


def _load_or_create_session(
    session: Session,
    session_id: int | None,
    user: User | None,
    language: str,
) -> ConversationSession:
    if session_id is not None:
        conv = session.get(ConversationSession, session_id)
        if conv is None:
            raise HTTPException(status_code=404, detail="Conversation not found")
        return conv
    conv = ConversationSession(
        user_id=user.id if user else None,
        language=language,
        messages_json=[],
        state_json={},
        last_active_at=datetime.now(timezone.utc),
    )
    session.add(conv)
    session.commit()
    session.refresh(conv)
    return conv


_PREFERENCE_HINTS = ("i love", "i like", "i prefer", "i'm into", "i am into", "i enjoy", "not into", "i hate", "i dislike")


@router.post("/agent/chat", response_model=AgentChatResponse, summary="Talk to the LocalIQ companion")
@limiter.limit(PUBLIC_LIMIT)
async def agent_chat(
    request: Request,
    response: Response,
    payload: AgentChatRequest,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """Conversational planning: extract constraints, ask, then recommend.

    Works signed-out (no taste vector) and with no Ollama (deterministic
    replies), so the app always has a working assistant.
    """
    language = payload.language or companion.detect_language(
        payload.message, (current_user.preferred_language if current_user else "en")
    )
    conv = _load_or_create_session(session, payload.session_id, current_user, language)
    history = list(conv.messages_json or [])
    history.append({"role": "user", "content": payload.message})

    extracted = await companion.extract_constraints(payload.message, history)
    state = companion.merge_constraints(dict(conv.state_json or {}), extracted)

    # Learn explicit preferences the user states in chat (PRD 4.6).
    if (
        current_user is not None
        and any(h in payload.message.lower() for h in _PREFERENCE_HINTS)
    ):
        taste.apply_explicit_text(session, current_user, payload.message, weight=1.5)

    conv.language = language
    conv.state_json = state

    # Resolve coordinates: explicit lat/lng wins, else the named area.
    lat, lng = payload.lat, payload.lng
    if (lat is None or lng is None) and state.get("location"):
        coords = resolve_location(str(state["location"]))
        if coords:
            lat, lng = coords

    question = companion.next_question(state, language)
    wants_recs = bool(extracted.get("wants_recommendations")) or bool(
        state.get("location") and state.get("time_hours")
    )

    mode = "chat"
    recommendations: list[AgentRecommendation] = []
    if wants_recs and (question is None or extracted.get("wants_recommendations")):
        mode = "recommend"
        try:
            weather = await fetch_weather(lat, lng) if lat is not None and lng is not None else await fetch_weather()
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Agent weather fetch failed: %s", exc)
            weather = neutral_weather(reason="exception")

        ranked = graphs.taste_aware_recommend(
            session,
            current_user,
            lat=lat,
            lng=lng,
            time_hours=state.get("time_hours"),
            budget_inr=state.get("budget_inr"),
            start_time=state.get("start_time"),
            weather=weather,
            limit=5,
        )
        recommendations = [
            AgentRecommendation(
                id=r.experience.id or 0,
                name=r.experience.name,
                category=r.experience.category,
                avg_cost=r.experience.avg_cost,
                area=None,
                why=r.why,
                score=r.score,
                distance_km=r.distance_km,
                travel_time_min=r.travel_time_min,
            )
            for r in ranked
        ]
        reply = await companion.compose_reply(
            state,
            [{"experience": r.experience, "why": r.why, "travel_time_min": r.travel_time_min} for r in ranked],
            language=language,
            taste_text=current_user.taste_profile_text if current_user else None,
        )
    elif question is not None:
        mode = "clarify"
        reply = question
    else:
        reply = await companion.compose_reply(state, [], language=language, question=None)
        if not reply:
            reply = "Tell me what you feel like doing and I'll plan it."

    history.append({"role": "assistant", "content": reply})
    conv.messages_json = history[-20:]
    conv.last_active_at = datetime.now(timezone.utc)
    session.add(conv)
    session.commit()
    session.refresh(conv)

    return AgentChatResponse(
        session_id=conv.id or 0,
        reply=reply,
        mode=mode,
        language=language,
        constraints=state,
        recommendations=recommendations,
    )


@router.post("/agent/guide", response_model=GuideResponse, summary="In-experience local tips")
@limiter.limit(PUBLIC_LIMIT)
async def agent_guide(
    request: Request,
    response: Response,
    payload: GuideRequest,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """Location-triggered guidance for a specific experience (PRD 4.10)."""
    exp = session.get(Experience, payload.experience_id)
    if exp is None:
        raise HTTPException(status_code=404, detail="Experience not found")
    language = payload.language or (current_user.preferred_language if current_user else "en")
    tips = await companion.compose_guide_tips(
        exp.name,
        category=exp.category,
        description=exp.description or "",
        language=language,
    )
    return GuideResponse(experience_id=exp.id or 0, name=exp.name, tips=tips)


@router.get(
    "/agent/sessions/{session_id}",
    response_model=SessionResponse,
    summary="Fetch a conversation's history and constraints",
)
@limiter.limit(PUBLIC_LIMIT)
def get_session_state(
    request: Request,
    response: Response,
    session_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    conv = session.get(ConversationSession, session_id)
    if conv is None:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return SessionResponse(
        session_id=conv.id or 0,
        language=conv.language,
        messages=list(conv.messages_json or []),
        constraints=dict(conv.state_json or {}),
    )
