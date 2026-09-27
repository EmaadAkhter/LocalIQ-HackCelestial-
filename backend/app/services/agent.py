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
    "You are LocalIQ Travel Buddy. Help users discover Mumbai places, guides, meetups, "
    "and itineraries. Use the available tools and the user's location. Only mention places "
    "or guides returned by a tool. Ask before booking or spending."
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
    """Strip filler words so the DB text search has a real signal."""
    words = [
        w.strip(".,!?;:'\"()[]{}").lower()
        for w in message.split()
        if w.strip(".,!?;:'\"()[]{}")
    ]
    kept = [w for w in words if w not in _STOP_WORDS and len(w) > 2]
    # Prefer the last content words (they are usually the location/topic).
    return " ".join(kept[-4:]) if kept else ""


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
    if not query:
        return result
    try:
        places = agent_tools.search_places(
            session, query=query, lat=lat, lng=lng, limit=8
        )
        result["places"] = [
            {**p, "description": (p.get("description") or "")[:180]}
            for p in places
        ]
    except Exception as exc:  # noqa: BLE001
        logger.warning("Pre-search places failed: %s", exc)
        result["places_error"] = str(exc)

    if "guide" in message.lower() or "expert" in message.lower():
        try:
            area = next(
                (w for w in query.split() if w in {"bandra", "colaba", "dadar", "juhu", "andheri", "powai"}),
                "",
            )
            result["guides"] = agent_tools.search_guides(
                session, area=area, limit=4
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
    """A deterministic reply that still searches real data.

    ponytail: keyword matching, not intent classification. The LLM path is the
    real agent; this exists so a bad key or a stopped Ollama never breaks chat.
    """
    words = [w.strip(".,!?").lower() for w in message.split() if len(w) > 3]
    stop = {"what", "where", "there", "about", "mumbai", "should", "could", "would", "have", "want", "good", "best"}
    keywords = [w for w in words if w not in stop]
    rows: list[dict] = []
    try:
        for word in keywords:
            rows = agent_tools.search_places(
                session, query=word, lat=lat, lng=lng, limit=3
            )
            if rows:
                break
    except Exception:  # noqa: BLE001
        rows = []
    if not rows:
        return (
            "I'm having trouble reaching my planning brain right now. "
            "Try naming a Mumbai area and an interest — for example "
            "'Bandra, food' or 'Colaba, history' — and I'll pull options."
        )
    lines = [f"- {r['name']} ({r['category']}, rated {r['rating']}/5, ~₹{r['avg_cost']})" for r in rows]
    return (
        "My live model is offline, but here are real LocalIQ picks I found for you:\n"
        + "\n".join(lines)
        + "\nAsk me to turn any of these into a plan."
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
                lines.append(f"• {name}{suffix}")
            if lines:
                return "Here is what I found:\n" + "\n".join(lines)
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
