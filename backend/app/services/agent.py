"""Travel Buddy agent: one LLM turn with optional tool calls.

The agent is deliberately simple:
- Build a system prompt that gives identity + available tools.
- Append conversation history.
- Call the LLM; if it requests tools, return a pending run for user confirmation.
- If confirmed (or no tools requested), execute tools and send results back to
  the LLM for the final answer.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from sqlmodel import Session

from app.models import AgentRun, Conversation, Message, MessageRole, User
from app.services import agent_tools, llm

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = (
    "You are LocalIQ Travel Buddy, a knowledgeable and enthusiastic local guide for Mumbai. "
    "Help users discover places, food, culture, guides, and itineraries. "
    "ALWAYS use real places returned by tools or the provided LocalIQ data — never invent names. "
    "Format your replies using Markdown: use **bold** for place names, bullet points for lists, "
    "and short headers (###) for sections. Keep replies concise but rich. "
    "When suggesting places, include the name, category, cost estimate, and a one-line why-visit. "
    "If the user asks about something near them, use the provided lat/lng context. "
    "Ask before booking or spending money."
)

_STOP_WORDS = {
    "i", "me", "my", "want", "looking", "find", "show", "tell", "about", "some", "any",
    "a", "an", "the", "in", "on", "at", "to", "for", "of", "and", "or", "with", "near",
    "by", "from", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had",
    "do", "does", "did", "can", "could", "would", "should", "will", "shall", "may", "might",
    "what", "where", "when", "which", "who", "why", "how", "there", "this", "that", "these",
    "those", "today", "tonight", "tomorrow", "now", "currently", "right", "good", "best",
    "great", "cheap", "quiet", "chilled", "nice", "amazing", "popular", "wallet-friendly",
    "budget", "affordable", "expensive", "quick", "short", "long", "full", "half", "hour",
    "hours", "minute", "minutes", "day", "days", "plan", "make", "give", "get", "recommend",
    "suggest", "list", "few", "couple", "many", "much", "more", "most", "very", "really",
    "just", "only", "also", "still", "even", "well", "so", "too", "mumbai", "localiq",
}


def _extract_search_terms(message: str) -> str:
    """Strip filler words so the DB text search has a real signal.

    Returns up to 5 content words — keeping more than 4 lets the search
    find broader matches on multi-topic queries like 'cheap rooftop bar Bandra'.
    """
    words = [
        w.strip(".,!?;:'\"()[]{}").lower()
        for w in message.split()
        if w.strip(".,!?;:'\"()[]{}")
    ]
    kept = [w for w in words if w not in _STOP_WORDS and len(w) > 2]
    # Return up to 5 kept words to preserve more signal
    return " ".join(kept[-5:]) if kept else ""


def _looks_like_place_query(message: str) -> bool:
    """Heuristic: does this look like a request for places/food/guides/activities?"""
    lowered = message.lower()
    intent_hints = {
        "food", "eat", "cafe", "coffee", "breakfast", "lunch", "dinner", "restaurant",
        "street food", "snack", "drink", "bar", "pub", "heritage", "walk", "tour", "visit",
        "see", "do", "explore", "experience", "activity", "place", "spot", "area",
        "neighbourhood", "bandra", "colaba", "dadar", "juhu", "andheri", "powai", "versova",
        "churchgate", "marine lines", "mahim", "parel", "wadala", "sion", "kurla", "chembur",
        "byculla", "fort", "cst", "csmt", "gateway", "crawford", "chor bazaar", "guide",
        "local", "expert", "itinerary", "plan", "trip", "meetup", "people", "join",
    }
    return any(h in lowered for h in intent_hints) or _extract_search_terms(message) != ""


def _pre_search(
    session: Session, message: str, lat: float | None, lng: float | None
) -> dict[str, Any]:
    """Look up real LocalIQ data before the LLM replies to place/food/guide queries."""
    result: dict[str, Any] = {}
    query = _extract_search_terms(message)

    # If extraction stripped everything, fall back to broader search.
    search_query = query if query else message[:50]

    try:
        places = agent_tools.search_places(
            session, query=search_query, lat=lat, lng=lng, limit=12
        )
        # If location-filtered results are too few, supplement with a global search.
        if len(places) < 4:
            more = agent_tools.search_places(
                session, query=search_query, lat=None, lng=None, limit=8
            )
            seen_ids = {p["id"] for p in places}
            places += [p for p in more if p["id"] not in seen_ids]
        result["places"] = [
            {**p, "description": (p.get("description") or "")[:200]}
            for p in places[:12]
        ]
    except Exception as exc:  # noqa: BLE001
        logger.warning("Pre-search places failed: %s", exc)
        result["places_error"] = str(exc)

    if "guide" in message.lower() or "expert" in message.lower():
        try:
            area = next(
                (w for w in (query or message).split() if w in {"bandra", "colaba", "dadar", "juhu", "andheri", "powai", "fort", "versova", "kurla", "parel"}),
                "",
            )
            result["guides"] = agent_tools.search_guides(
                session, area=area, limit=6
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("Pre-search guides failed: %s", exc)
            result["guides_error"] = str(exc)
    return result


def _build_messages(
    conversation: Conversation,
    user_message: Message,
) -> list[dict[str, Any]]:
    """Rebuild the message list for the LLM from the conversation."""
    msgs: list[dict[str, Any]] = [{"role": "system", "content": _SYSTEM_PROMPT}]
    for m in conversation.messages:
        # Only the spoken content matters for continuity; tool-call plumbing
        # stays inside the turn it belongs to.
        msgs.append({"role": m.role, "content": m.content})
    return msgs


def _fallback_reply(
    session: Session, message: str, lat: float | None, lng: float | None
) -> str:
    """A deterministic, markdown-formatted reply that still searches real data."""
    words = [w.strip(".,!?").lower() for w in message.split() if len(w) > 3]
    stop = {"what", "where", "there", "about", "mumbai", "should", "could", "would",
            "have", "want", "good", "best", "show", "tell", "find", "some", "near"}
    keywords = [w for w in words if w not in stop]
    rows: list[dict] = []
    try:
        # Try each keyword and accumulate up to 6 unique results
        seen_ids: set = set()
        for word in keywords:
            hits = agent_tools.search_places(
                session, query=word, lat=lat, lng=lng, limit=4
            )
            for h in hits:
                if h["id"] not in seen_ids:
                    seen_ids.add(h["id"])
                    rows.append(h)
                if len(rows) >= 6:
                    break
            if len(rows) >= 6:
                break
        # If still nothing, do a broader search with no keyword filter
        if not rows:
            rows = agent_tools.search_places(
                session, query="", lat=lat, lng=lng, limit=6
            )
    except Exception:  # noqa: BLE001
        rows = []
    if not rows:
        return (
            "I'm having trouble reaching my planning brain right now. "
            "Try naming a Mumbai area and an interest — for example "
            "**Bandra, coffee** or **Colaba, heritage** — and I'll pull options."
        )
    lines = [
        f"- **{r['name']}** ({r['category']}, ⭐ {r['rating']}/5, ~₹{r['avg_cost']})"
        for r in rows
    ]
    return (
        "My live model is offline, but here are real LocalIQ picks I found:\n\n"
        + "\n".join(lines)
        + "\n\nAsk me to turn any of these into a plan!"
    )


def _execute_calls(
    session: Session, tool_calls: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Run each tool call, turning failures into data the model can explain."""
    results: list[dict[str, Any]] = []
    for call in tool_calls:
        try:
            result = agent_tools.execute(
                call["name"], session, call.get("arguments", {})
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("Tool %s failed: %s", call["name"], exc)
            result = {"error": str(exc)}
        results.append({"tool_call_id": call.get("id", ""), "result": result})
    return results


def _summarize_results(results: list[dict[str, Any]]) -> str:
    """Deterministic reply built from the last tool results.

    Ollama sometimes returns an empty assistant turn right after a tool call.
    Rather than show the user a blank bubble, list what the tools actually
    returned. It never invents data — only what is in the payload.
    """
    for entry in reversed(results):
        payload = entry.get("result")
        if isinstance(payload, list) and payload:
            lines: list[str] = []
            for item in payload[:5]:
                name = item.get("name")
                if not name:
                    continue
                bits: list[str] = []
                if item.get("category"):
                    bits.append(str(item["category"]))
                if item.get("rating"):
                    bits.append(f"{item['rating']}/5")
                if item.get("avg_cost") is not None:
                    bits.append(f"~₹{item['avg_cost']}")
                suffix = f" ({', '.join(bits)})" if bits else ""
                lines.append(f"- **{name}**{suffix}")
            if lines:
                return "### Here's what I found\n\n" + "\n".join(lines)
        if isinstance(payload, dict):
            if payload.get("name"):
                return f"{payload['name']} — {(payload.get('description') or '')[:160]}".strip()
            if payload.get("error"):
                return f"I could not complete that lookup: {payload['error']}"
    return ""


def _create_run(
    session: Session,
    user: User,
    conversation: Conversation,
    status: str,
    tool_calls: list[dict[str, Any]],
    result: str | None = None,
) -> AgentRun:
    run = AgentRun(
        user_id=user.id,
        conversation_id=conversation.id,
        status=status,
        tool_calls_json=tool_calls,
        result=result,
    )
    session.add(run)
    session.commit()
    session.refresh(run)
    return run


async def run_turn(
    session: Session,
    user: User,
    conversation: Conversation,
    user_message: Message,
    confirm: bool = False,
    pending_run: AgentRun | None = None,
    lat: float | None = None,
    lng: float | None = None,
) -> dict[str, Any]:
    """Execute one agent turn.

    Returns a dict with:
      - run_id, conversation_id, status
      - assistant_message (the persisted Message)
      - pending_tool_calls (if waiting for confirmation)
    """
    messages = _build_messages(conversation, user_message)

    # Prime the LLM with real, location-ranked data so every place answer is
    # grounded in the actual database instead of the model's training memory.
    if _looks_like_place_query(user_message.content):
        context = _pre_search(session, user_message.content, lat, lng)
        loc_note = ""
        if lat is not None and lng is not None:
            loc_note = f"The user is at lat={lat}, lng={lng}. Use nearby results. "
        messages.append({
            "role": "system",
            "content": loc_note + "Relevant LocalIQ results: " + json.dumps(context, default=str),
        })

    # A confirmed pending run already has its tool calls decided; execute them
    # and feed the results back so the model can write the final answer.
    if pending_run and confirm:
        calls = pending_run.tool_calls_json
        results = _execute_calls(session, calls)
        messages.append({
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {
                    "id": c["id"],
                    "type": "function",
                    "function": {"name": c["name"], "arguments": json.dumps(c["arguments"])},
                }
                for c in calls
            ],
        })
        for r in results:
            messages.append({
                "role": "tool",
                "tool_call_id": r["tool_call_id"],
                "content": json.dumps(r["result"], default=str),
            })
        pending_run.status = "completed"
        session.add(pending_run)

    tools = agent_tools.schemas()
    all_tool_calls: list[dict[str, Any]] = []
    last_results: list[dict[str, Any]] = []
    content = ""
    status = "completed"
    run: AgentRun | None = None

    # Read-only tools run inline; only mutating tools pause for confirmation.
    for _ in range(4):
        try:
            response = await llm.chat_completion(messages, tools=tools)
            msg = llm.extract_message(response)
            content = msg.get("content") or ""
            tool_calls = llm.extract_tool_calls(msg)
        except Exception as exc:  # noqa: BLE001
            # The agent must never 500 the app. Degrade to a deterministic,
            # data-grounded reply so the user still gets something useful.
            logger.warning("Agent LLM unavailable, using fallback: %s", exc)
            content = _fallback_reply(session, user_message.content, lat, lng)
            tool_calls = []

        if not tool_calls:
            break

        all_tool_calls.extend(tool_calls)
        needs_confirmation = any(
            c["name"] in agent_tools.MUTATING_TOOLS for c in tool_calls
        )
        if needs_confirmation and not confirm:
            run = _create_run(session, user, conversation, "pending", tool_calls)
            status = "pending_confirmation"
            content = content or "Shall I go ahead?"
            break

        last_results = _execute_calls(session, tool_calls)
        messages.append({
            "role": "assistant",
            "content": content,
            "tool_calls": [
                {
                    "id": c["id"],
                    "type": "function",
                    "function": {"name": c["name"], "arguments": json.dumps(c["arguments"])},
                }
                for c in tool_calls
            ],
        })
        for r in last_results:
            messages.append({
                "role": "tool",
                "tool_call_id": r["tool_call_id"],
                "content": json.dumps(r["result"], default=str),
            })

    # The model occasionally answers a tool result with an empty turn. Showing a
    # blank bubble is worse than a plain list of what the tools actually found.
    if not content.strip():
        content = (
            _summarize_results(last_results)
            or _fallback_reply(session, user_message.content, lat, lng)
        )
        status = "completed"

    assistant_message = Message(
        conversation_id=conversation.id,
        role=MessageRole.ASSISTANT.value,
        content=content,
        tool_json={"tool_calls": all_tool_calls} if all_tool_calls else {},
    )
    session.add(assistant_message)

    if run is None:
        run = _create_run(session, user, conversation, "completed", all_tool_calls, content)

    conversation.updated_at = __import__("app.timeutil", fromlist=["utcnow"]).utcnow()
    session.add(conversation)
    session.commit()
    session.refresh(assistant_message)
    session.refresh(run)

    return {
        "run_id": run.id,
        "conversation_id": conversation.id,
        "status": status,
        "assistant_message": assistant_message,
        "pending_tool_calls": tool_calls if status == "pending_confirmation" else [],
    }
