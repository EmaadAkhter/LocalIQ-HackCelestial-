"""Tiny thread-safe in-memory TTL cache.

Used to memoise identical LLM prompts. Single-process by design; a shared cache
(Redis) would be needed for a multi-replica deployment.
"""

from __future__ import annotations

import threading
import time
from collections import OrderedDict
from typing import Any


class TTLCache:
    """Bounded LRU + TTL cache."""

    def __init__(self, maxsize: int = 256, ttl_seconds: float = 300.0) -> None:
        self._maxsize = max(1, maxsize)
        self._ttl = max(0.01, float(ttl_seconds))
        self._lock = threading.Lock()
        self._data: OrderedDict[str, tuple[float, Any]] = OrderedDict()
        self.hits = 0
        self.misses = 0

    def get(self, key: str) -> Any | None:
        now = time.monotonic()
        with self._lock:
            item = self._data.get(key)
            if item is None:
                self.misses += 1
                return None
            expires_at, value = item
            if now >= expires_at:
                del self._data[key]
                self.misses += 1
                return None
            self._data.move_to_end(key)
            self.hits += 1
            return value

    def set(self, key: str, value: Any) -> None:
        expires_at = time.monotonic() + self._ttl
        with self._lock:
            self._data[key] = (expires_at, value)
            self._data.move_to_end(key)
            while len(self._data) > self._maxsize:
                self._data.popitem(last=False)

    def clear(self) -> None:
        with self._lock:
            self._data.clear()

    def stats(self) -> dict[str, int]:
        with self._lock:
            return {"size": len(self._data), "hits": self.hits, "misses": self.misses}
