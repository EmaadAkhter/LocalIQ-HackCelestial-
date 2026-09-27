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
) -> list[dict[str, Any]]:
    """Rebuild the message list for the LLM from the conversation."""
    msgs: list[dict[str, Any]] = [{"role": "system", "content": _SYSTEM_PROMPT}]
    for m in conversation.messages:
        # Only the spoken content matters for continuity; tool-call plumbing
        # stays inside the turn it belongs to.
        msgs.append({"role": m.role, "content": m.content})
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
    messages = _build_messages(conversation, user_message)

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
            content = _fallback_reply(session, user_message.content)
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

        results = _execute_calls(session, tool_calls)
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
        for r in results:
            messages.append({
                "role": "tool",
                "tool_call_id": r["tool_call_id"],
                "content": json.dumps(r["result"], default=str),
            })

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
