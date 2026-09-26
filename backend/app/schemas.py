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
