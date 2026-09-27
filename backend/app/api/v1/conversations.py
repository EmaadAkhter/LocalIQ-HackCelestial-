"""Persistent chat + Travel Buddy agent endpoints.

- Conversations are long-lived threads (general, travel_buddy, guide, meetup).
- Messages are stored per conversation.
- The Travel Buddy agent uses a conversation + AgentRun for tool calling and
  confirmation-before-action.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlmodel import Session, desc, select

from app.database import get_session
from app.models import AgentRun, Conversation, ConversationKind, Message, MessageRole, User
from app.rate_limit import LLM_LIMIT, PUBLIC_LIMIT, limiter
from app.schemas import (
    AgentChatRequest,
    AgentChatResponse,
    AgentPendingAction,
    ChatMessageResponse,
    ConversationCreateRequest,
    ConversationResponse,
    MessageResponse,
    ToolCall,
)
from app.services import agent
from app.services.auth import get_current_user, get_current_user_optional

logger = logging.getLogger(__name__)
router = APIRouter()


def _conversation_or_404(session: Session, conversation_id: int, user_id: int) -> Conversation:
    conv = session.get(Conversation, conversation_id)
    if conv is None or conv.user_id != user_id:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return conv


def _message_response(m: Message) -> MessageResponse:
    return MessageResponse(
        id=m.id,
        role=m.role,
        content=m.content,
        created_at=m.created_at,
        tool_json=m.tool_json or {},
    )


@router.get("/conversations", response_model=list[ConversationResponse], summary="List my conversations")
@limiter.limit(PUBLIC_LIMIT)
def list_conversations(
    request: Request,
    response: Response,
    kind: str | None = None,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    stmt = select(Conversation).where(Conversation.user_id == current_user.id)
    if kind:
        stmt = stmt.where(Conversation.kind == kind)
    stmt = stmt.order_by(desc(Conversation.updated_at))
    rows = list(session.exec(stmt).all())
    return [
        ConversationResponse(
            id=c.id,
            kind=c.kind,
            title=c.title,
            created_at=c.created_at,
            updated_at=c.updated_at,
        )
        for c in rows
    ]


@router.post("/conversations", response_model=ConversationResponse, summary="Start a conversation")
@limiter.limit(PUBLIC_LIMIT)
def create_conversation(
    request: Request,
    response: Response,
    payload: ConversationCreateRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    conv = Conversation(
        user_id=current_user.id,
        kind=payload.kind,
        title=payload.title,
        data_json=payload.data_json,
    )
    session.add(conv)
    session.commit()
    session.refresh(conv)
    return ConversationResponse(
        id=conv.id,
        kind=conv.kind,
        title=conv.title,
        created_at=conv.created_at,
        updated_at=conv.updated_at,
    )


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=list[MessageResponse],
    summary="Get messages in a conversation",
)
@limiter.limit(PUBLIC_LIMIT)
def get_messages(
    request: Request,
    response: Response,
    conversation_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    conv = _conversation_or_404(session, conversation_id, current_user.id)
    stmt = (
        select(Message)
        .where(Message.conversation_id == conv.id)
        .order_by(Message.created_at)
    )
    rows = list(session.exec(stmt).all())
    return [_message_response(m) for m in rows]



@router.post("/travel-buddy/chat", response_model=AgentChatResponse, summary="Chat with the Travel Buddy agent")
@limiter.limit(LLM_LIMIT)
async def travel_buddy_chat(
    request: Request,
    response: Response,
    payload: AgentChatRequest,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """Agentic chat with tool calling and confirmation-before-action."""
    if current_user is None:
        current_user = session.exec(select(User).limit(1)).first()
        if current_user is None:
            current_user = User(
                display_name="Guest Explorer",
                email="guest@localiq.app",
                provider="guest",
                tier="guest",
            )
            session.add(current_user)
            session.commit()
            session.refresh(current_user)

    if payload.conversation_id:
        conv = _conversation_or_404(session, payload.conversation_id, current_user.id)
    else:
        conv = Conversation(
            user_id=current_user.id,
            kind=ConversationKind.TRAVEL_BUDDY.value,
            title="Travel Buddy",
        )
        session.add(conv)
        session.commit()
        session.refresh(conv)

    user_msg = Message(
        conversation_id=conv.id,
        role=MessageRole.USER.value,
        content=payload.message,
    )
    session.add(user_msg)
    session.commit()
    session.refresh(user_msg)

    pending_run: AgentRun | None = None
    if not payload.confirm:
        # Look for the most recent pending run on this conversation.
        stmt = (
            select(AgentRun)
            .where(AgentRun.conversation_id == conv.id, AgentRun.status == "pending")
            .order_by(desc(AgentRun.created_at))
        )
        pending_run = session.exec(stmt).first()

    result = await agent.run_turn(
        session,
        current_user,
        conv,
        user_msg,
        confirm=payload.confirm,
        pending_run=pending_run,
        lat=payload.lat,
        lng=payload.lng,
    )

    assistant = _message_response(result["assistant_message"])
    pending = [
        ToolCall(id=c["id"], name=c["name"], arguments=c["arguments"])
        for c in result["pending_tool_calls"]
    ]

    return AgentChatResponse(
        conversation_id=conv.id,
        run_id=result["run_id"],
        status=result["status"],
        message=assistant,
        pending_actions=pending,
    )
