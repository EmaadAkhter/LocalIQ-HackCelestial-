"""Tests for the persistent chat + Travel Buddy endpoints."""

from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient

from main import app
from app.models import Conversation, ConversationKind, Message, MessageRole

client = TestClient(app)


@pytest.fixture
def auth_headers() -> dict:
    """Register a test user and return bearer headers."""
    email = f"chat-{uuid.uuid4().hex[:10]}@tavesglobal.com"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Chat User", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201
    token = r.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_create_and_list_conversations(auth_headers: dict):
    r = client.post("/api/v1/conversations", json={"kind": "general", "title": "Trip chat"}, headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["kind"] == "general"
    assert body["title"] == "Trip chat"

    r = client.get("/api/v1/conversations", headers=auth_headers)
    assert r.status_code == 200
    items = r.json()
    assert len(items) == 1
    assert items[0]["title"] == "Trip chat"


def test_list_conversations_filter_by_kind(auth_headers: dict):
    client.post("/api/v1/conversations", json={"kind": "travel_buddy", "title": "Buddy"}, headers=auth_headers)
    client.post("/api/v1/conversations", json={"kind": "guide", "title": "Guide"}, headers=auth_headers)

    r = client.get("/api/v1/conversations?kind=travel_buddy", headers=auth_headers)
    assert r.status_code == 200
    items = r.json()
    assert len(items) == 1
    assert items[0]["kind"] == "travel_buddy"


def test_get_messages_empty(auth_headers: dict):
    r = client.post("/api/v1/conversations", json={"kind": "general"}, headers=auth_headers)
    conv_id = r.json()["id"]

    r = client.get(f"/api/v1/conversations/{conv_id}/messages", headers=auth_headers)
    assert r.status_code == 200
    assert r.json() == []


def test_cannot_read_other_users_conversation(auth_headers: dict):
    r = client.post("/api/v1/conversations", json={"kind": "general"}, headers=auth_headers)
    conv_id = r.json()["id"]

    # Register a second user by hand.
    other_email = f"other-{uuid.uuid4().hex[:10]}@tavesglobal.com"
    client.post("/api/v1/auth/register", json={"name": "Other", "email": other_email, "password": "Secret123"})
    login = client.post("/api/v1/auth/login", json={"email": other_email, "password": "Secret123"})
    other_token = login.json()["access_token"]
    other_headers = {"Authorization": f"Bearer {other_token}"}

    r = client.get(f"/api/v1/conversations/{conv_id}/messages", headers=other_headers)
    assert r.status_code == 404


def test_travel_buddy_chat_creates_conversation(auth_headers: dict, monkeypatch):
    # Avoid calling the real LLM in tests.
    async def fake_chat_completion(messages, tools=None):
        return {"choices": [{"message": {"role": "assistant", "content": "Hello from tests"}}]}

    monkeypatch.setattr("app.services.llm.chat_completion", fake_chat_completion)

    r = client.post("/api/v1/travel-buddy/chat", json={"message": "Hi"}, headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "completed"
    assert body["message"]["role"] == "assistant"
    assert body["message"]["content"] == "Hello from tests"
    assert body["conversation_id"] is not None


def test_travel_buddy_requires_auth():
    r = client.post("/api/v1/travel-buddy/chat", json={"message": "Hi"})
    assert r.status_code == 401
