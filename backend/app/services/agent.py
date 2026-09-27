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
    "You are LocalIQ Travel Buddy, a warm, knowledgeable Mumbai travel companion. "
    "You help travellers discover places, find local guides, join meetups, and build "
    "day-by-day itineraries. Use the tools available to you when you need real data. "
    "Before spending any action that costs money or creates a booking, ask the user to "
    "confirm. Keep replies concise, friendly, and actionable."
)


def _build_messages(
    conversation: Conversation,
    user_message: Message,
    tool_results: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Rebuild the message list for the LLM from the conversation."""
    msgs: list[dict[str, Any]] = [{"role": "system", "content": _SYSTEM_PROMPT}]
    for m in conversation.messages:
        item: dict[str, Any] = {"role": m.role, "content": m.content}
        if m.tool_json and m.role == "assistant":
            item["tool_calls"] = m.tool_json.get("tool_calls", [])
        if m.role == "tool":
            item["tool_call_id"] = m.tool_json.get("tool_call_id", "")
        msgs.append(item)
    # The user's new message is already persisted, but tool results are not.
    if tool_results:
        for tr in tool_results:
            msgs.append({
                "role": "tool",
                "tool_call_id": tr["tool_call_id"],
                "content": json.dumps(tr["result"], default=str),
            })
    return msgs


def _fallback_reply(session: Session, message: str) -> str:
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
            rows = agent_tools.search_places(session, query=word, limit=3)
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
) -> dict[str, Any]:
    """Execute one agent turn.

    Returns a dict with:
      - run_id, conversation_id, status
      - assistant_message (the persisted Message)
      - pending_tool_calls (if waiting for confirmation)
    """
    tool_results: list[dict[str, Any]] | None = None

    if pending_run and confirm:
        # Execute the pending tool calls and ask the LLM for a final answer.
        tool_results = []
        for call in pending_run.tool_calls_json:
            try:
                result = agent_tools.execute(
                    call["name"], session, call.get("arguments", {})
                )
            except Exception as exc:  # noqa: BLE001
                logger.warning("Tool %s failed: %s", call["name"], exc)
                result = {"error": str(exc)}
            tool_results.append({
                "tool_call_id": call.get("id", ""),
                "result": result,
            })
        pending_run.status = "completed"
        session.add(pending_run)

    messages = _build_messages(conversation, user_message, tool_results)
    tools = agent_tools.schemas()

    try:
        response = await llm.chat_completion(messages, tools=tools)
        msg = llm.extract_message(response)
        content = msg.get("content") or ""
        tool_calls = llm.extract_tool_calls(msg)
    except Exception as exc:  # noqa: BLE001
        # The agent must never 500 the app. Degrade to a deterministic,
        # data-grounded reply so the user still gets something useful.
        logger.warning("Agent LLM unavailable, using fallback: %s", exc)
        content = _fallback_reply(session, user_message.content)
        tool_calls = []

    assistant_message = Message(
        conversation_id=conversation.id,
        role=MessageRole.ASSISTANT.value,
        content=content,
        tool_json={"tool_calls": tool_calls} if tool_calls else {},
    )
    session.add(assistant_message)

    if tool_calls and not confirm:
        # First time seeing tool calls: ask for confirmation before spending.
        run = _create_run(session, user, conversation, "pending", tool_calls)
        status = "pending_confirmation"
    else:
        run = _create_run(session, user, conversation, "completed", tool_calls, content)
        status = "completed"

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
