"""Context-aware AI guide chat, scoped to a single experience."""

from __future__ import annotations

from app.config import get_settings
from app.schemas import ChatRequest, ChatResponse, ExperienceContext
from app.services.llm import LLMError, chat

GUIDE_SYSTEM_PROMPT = """\
You are LocalIQ's on-the-ground local guide for one specific experience.
Answer only about THIS experience, using the context below. Be concise (2-4 sentences),
practical and honest.

Rules:
- Never invent specific prices, opening hours, menu items, dish/drink names, or attraction names.
- If the context does not cover something, give short general local advice instead of making up specifics.
- Never change the subject.

Experience context:
{context}"""


def _format_context(experience: ExperienceContext) -> str:
    rows = (
        ("Name", experience.name),
        ("Category", experience.category),
        ("Area", experience.area),
        ("Description", experience.description),
        ("Price (INR)", experience.price_inr),
        ("Typical duration (min)", experience.duration_minutes),
        ("Opening hours", experience.opening_hours),
        ("Rating", experience.rating),
    )
    return "\n".join(f"- {label}: {value}" for label, value in rows if value is not None)


def build_system_prompt(experience: ExperienceContext) -> str:
    return GUIDE_SYSTEM_PROMPT.format(context=_format_context(experience))


def _canned_reply(experience: ExperienceContext, message: str) -> str:
    text = message.lower()
    if "kid" in text or "child" in text or "family" in text:
        if experience.category and "nightlife" in experience.category.lower():
            return (
                f"{experience.name} is really a nightlife spot, so it isn't well suited to children. "
                "Ask me for a family-friendly alternative in the same area."
            )
        return (
            f"Yes, {experience.name} generally works for families. Go earlier in the day when it is "
            "quieter, and carry water and snacks for the little ones."
        )
    if "time" in text or "when" in text or "crowd" in text:
        return (
            f"For {experience.name}, aim for the early morning or late afternoon to avoid the biggest "
            "crowds. Weekend evenings get busy."
        )
    if experience.description:
        return f"{experience.name}: {experience.description}"
    return (
        f"Happy to help with {experience.name}. "
        "What would you like to know - timing, cost, or nearby options?"
    )


async def answer(request: ChatRequest) -> ChatResponse:
    """Answer a question about an experience, falling back to canned text if needed."""
    settings = get_settings()

    if settings.demo_mode:
        return ChatResponse(reply=_canned_reply(request.experience, request.message), source="canned")

    messages = [{"role": "system", "content": build_system_prompt(request.experience)}]
    for turn in request.history[-8:]:
        messages.append({"role": turn.role, "content": turn.content})
    messages.append({"role": "user", "content": request.message})

    try:
        reply = await chat(messages)
    except LLMError:
        return ChatResponse(reply=_canned_reply(request.experience, request.message), source="canned")

    reply = reply.strip()
    if not reply:
        return ChatResponse(reply=_canned_reply(request.experience, request.message), source="canned")
    return ChatResponse(reply=reply, source="llm")
