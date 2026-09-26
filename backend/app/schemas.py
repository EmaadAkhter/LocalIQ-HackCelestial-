"""Pydantic schemas shared across the API."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

GroupType = Literal["solo", "couple", "family", "friends"]
ParseSource = Literal["llm", "heuristic", "canned"]


class Constraints(BaseModel):
    """Structured traveller constraints extracted from free text."""

    location: str = "Mumbai"
    time_hours: float = Field(default=2.0, ge=0.5, le=12)
    budget_inr: int = Field(default=1000, ge=0)
    group_type: GroupType = "solo"
    interests: list[str] = Field(default_factory=list)
    accessibility: list[str] = Field(default_factory=list)
    start_time: str | None = None


class ParseRequest(BaseModel):
    """Natural-language input to be turned into constraints."""

    text: str = Field(min_length=1, max_length=1000)


class ParseResponse(BaseModel):
    """Parsed constraints plus how they were derived."""

    constraints: Constraints
    source: ParseSource


class ExperienceContext(BaseModel):
    """Minimal experience context used to scope the AI guide chat."""

    id: str | None = None
    name: str
    category: str | None = None
    description: str | None = None
    price_inr: int | None = None
    duration_minutes: int | None = None
    opening_hours: str | None = None
    area: str | None = None
    rating: float | None = None


class ChatMessage(BaseModel):
    """A single turn in the guide conversation."""

    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    """A question about a specific experience."""

    experience: ExperienceContext
    message: str = Field(min_length=1, max_length=1000)
    history: list[ChatMessage] = Field(default_factory=list)


class ChatResponse(BaseModel):
    """The guide's reply."""

    reply: str
    source: Literal["llm", "canned"]


class ScoreFactors(BaseModel):
    """Per-experience evaluation inputs used to generate 'why this fits' text."""

    interest_matches: list[str] = Field(default_factory=list)
    time_fit: float = Field(default=1.0, ge=0, le=1)
    budget_fit: float = Field(default=1.0, ge=0, le=1)
    distance_km: float | None = None
    travel_minutes: int | None = None
    rating: float | None = None
    open_now: bool | None = None
    setting: Literal["indoor", "outdoor", "either"] | None = None
