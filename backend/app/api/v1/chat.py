"""AI guide chat (Ollama experience-grounded + data fallback)."""

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlmodel import Session

from app.database import get_session
from app.models import Experience
from app.rate_limit import LLM_LIMIT, limiter
from app.schemas import ChatRequest, ChatResponse
from app.services.llm import get_client

logger = logging.getLogger(__name__)
router = APIRouter()

GUIDE_SYSTEM = (
    "You are LocalIQ, a friendly Mumbai local guide. Answer ONLY about the given experience. "
    "Be concise (under 120 words), practical, and enthusiastic. Include one tip on timing, "
    "cost, or how to reach. If asked something unrelated, gently steer back to the experience."
)


def build_experience_context(exp: Experience) -> str:
    tags = ", ".join(exp.tags or [])
    return (
        f"Experience: {exp.name} (category: {exp.category})\n"
        f"Hours: {exp.open_time}-{exp.close_time}, avg cost ₹{exp.avg_cost}, "
        f"duration ~{exp.duration_min}min, rating {exp.rating}/5\n"
        f"Location: {exp.lat},{exp.lng} ({exp.indoor_outdoor})\n"
        f"Tags: {tags}\n"
        f"Description: {exp.description}"
    )


def fallback_reply(exp: Experience | None, message: str) -> str:
    low = message.lower()
    if exp is None:
        return (
            "I couldn't find that experience, but I can still help! Tell me your area, "
            "budget and hours — e.g. 'Bandra, 4 hours, ₹1500, food and art' — and I'll suggest options."
        )
    if any(k in low for k in ("reach", "go", "location", "address", "metro", "train", "auto", "cab")):
        return (
            f"{exp.name} is at {exp.lat:.4f},{exp.lng:.4f}. Easiest: local train + short auto/cab ride. "
            f"Open {exp.open_time}-{exp.close_time}; budget ~₹{exp.avg_cost} and ~{exp.duration_min}min. "
            f"Tip: go early to beat crowds."
        )
    if any(k in low for k in ("cost", "price", "budget", "expensive", "cheap")):
        return (
            f"{exp.name} averages ~₹{exp.avg_cost} per person for ~{exp.duration_min}min. "
            f"Rated {exp.rating}/5. Carry a little extra for snacks and auto fare."
        )
    if any(k in low for k in ("time", "hour", "open", "close", "when", "duration", "long")):
        return (
            f"{exp.name} is open {exp.open_time}-{exp.close_time} and takes ~{exp.duration_min}min. "
            f"Best in the morning on weekdays. {exp.description[:160]}"
        )
    if any(k in low for k in ("kid", "child", "family", "safe", "wheelchair", "accessible")):
        flags = ", ".join(exp.accessibility_flags or []) or "check with venue"
        return (
            f"For family/access needs at {exp.name}: accessibility notes say '{flags}'. "
            f"It's a {exp.indoor_outdoor} experience rated {exp.rating}/5. Mornings are calmest for kids."
        )
    return (
        f"{exp.name} ({exp.category}, {exp.rating}/5): {exp.description[:220]} "
        f"Plan ~{exp.duration_min}min and ~₹{exp.avg_cost}. Open {exp.open_time}-{exp.close_time}. "
        f"Tip: combine it with something nearby to save travel time!"
    )


@router.post("/chat", response_model=ChatResponse, summary="Chat with an experience guide")
@limiter.limit(LLM_LIMIT)
async def chat(
    request: Request,
    response: Response,
    payload: ChatRequest,
    session: Session = Depends(get_session),
):
    """Experience-grounded guide chat with graceful Ollama fallback."""
    exp = session.get(Experience, payload.experience_id) if payload.experience_id else None
    if payload.experience_id and not exp:
        raise HTTPException(status_code=404, detail="Experience not found")

    # Try Ollama when an experience context exists.
    if exp is not None:
        try:
            history = "\n".join(f"{m.role}: {m.content[:400]}" for m in payload.history[-6:])
            prompt = (
                f"{build_experience_context(exp)}\n"
                f"{('Conversation so far:\n' + history + chr(10)) if history else ''}"
                f"Visitor: {payload.message}\nGuide:"
            )
            client = get_client()
            text = await client.generate(prompt, system=GUIDE_SYSTEM)
            if text:
                return ChatResponse(
                    reply=text.strip(), fallback=False, experience_id=exp.id, source="ollama"
                )
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Chat LLM failed: %s", exc)

    return ChatResponse(
        reply=fallback_reply(exp, payload.message),
        fallback=True,
        experience_id=exp.id if exp else None,
        source="canned",
    )
