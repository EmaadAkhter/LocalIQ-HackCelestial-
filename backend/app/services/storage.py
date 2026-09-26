"""Self-hosted object storage for media (S3-compatible, filesystem fallback).

Used for experience photos pulled from Google Places and for generated assets
(share cards). The S3 client is created lazily and the backend is probed once:
if the store is disabled or unreachable, every call transparently uses
``settings.media_root`` instead, so local dev and the test suite never need a
running MinIO/s3mock.

Objects are addressed by a key like ``experiences/42/ab12.jpg`` and exposed to
clients either through ``s3_public_base_url`` or the ``/media/{key}`` proxy.
"""

from __future__ import annotations

import logging
import mimetypes
from pathlib import Path
from typing import Any

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)

_client: Any = None
_backend: str | None = None


def reset() -> None:
    """Forget the cached client/backend (used by tests)."""
    global _client, _backend
    _client = None
    _backend = None


def _settings():
    return get_settings()


def _fs_root() -> Path:
    root = Path(_settings().media_root)
    root.mkdir(parents=True, exist_ok=True)
    return root


def client() -> Any:
    """Lazily build the boto3 S3 client."""
    global _client
    if _client is None:
        import boto3
        from botocore.config import Config

        settings = _settings()
        _client = boto3.client(
            "s3",
            endpoint_url=settings.s3_endpoint,
            aws_access_key_id=settings.s3_access_key,
            aws_secret_access_key=settings.s3_secret_key,
            region_name=settings.s3_region,
            use_ssl=settings.s3_use_ssl,
            config=Config(
                s3={"addressing_style": settings.s3_addressing_style},
                connect_timeout=3,
                read_timeout=10,
                retries={"max_attempts": 1},
            ),
        )
    return _client


def ensure_bucket() -> None:
    """Create the bucket if it does not exist."""
    settings = _settings()
    s3 = client()
    try:
        s3.head_bucket(Bucket=settings.s3_bucket)
    except Exception:
        s3.create_bucket(Bucket=settings.s3_bucket)


def backend_name() -> str:
    """``"s3"`` when the object store is usable, else ``"filesystem"``.

    Probed once and cached; a failure is logged and never re-raised so a dead
    object store degrades to local files instead of breaking a request.
    """
    global _backend
    if _backend is not None:
        return _backend
    settings = _settings()
    if not settings.s3_enabled:
        _backend = "filesystem"
        return _backend
    try:
        ensure_bucket()
        _backend = "s3"
    except Exception as exc:
        logger.warning("S3 unavailable (%s); falling back to filesystem media", exc)
        _backend = "filesystem"
    return _backend


def _guess_content_type(key: str, fallback: str = "application/octet-stream") -> str:
    guessed, _ = mimetypes.guess_type(key)
    return guessed or fallback


def upload_bytes(key: str, data: bytes, content_type: str | None = None) -> str:
    """Store ``data`` under ``key``; returns the key. Never raises."""
    settings = _settings()
    content_type = content_type or _guess_content_type(key)
    if backend_name() == "s3":
        try:
            client().put_object(
                Bucket=settings.s3_bucket,
                Key=key,
                Body=data,
                ContentType=content_type,
            )
            return key
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("S3 put failed for %s (%s); writing to filesystem", key, exc)
    path = _fs_root() / key
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return key


async def upload_from_url(url: str, key: str) -> str | None:
    """Download ``url`` and store it under ``key``. Returns the key or None."""
    try:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as http:
            response = await http.get(url)
            response.raise_for_status()
            content_type = response.headers.get("content-type", "image/jpeg")
            return upload_bytes(key, response.content, content_type)
    except Exception as exc:
        logger.warning("Download for storage failed (%s): %s", url, exc)
        return None


def get_object(key: str) -> tuple[bytes, str] | None:
    """Return ``(bytes, content_type)`` for a key, or None if missing."""
    settings = _settings()
    if backend_name() == "s3":
        try:
            obj = client().get_object(Bucket=settings.s3_bucket, Key=key)
            data = obj["Body"].read()
            return data, obj.get("ContentType") or _guess_content_type(key)
        except Exception as exc:
            logger.debug("S3 get miss for %s: %s", key, exc)
    path = _fs_root() / key
    if path.is_file():
        return path.read_bytes(), _guess_content_type(key)
    return None


def object_exists(key: str) -> bool:
    settings = _settings()
    if backend_name() == "s3":
        try:
            client().head_object(Bucket=settings.s3_bucket, Key=key)
            return True
        except Exception:
            return False
    return (_fs_root() / key).is_file()


def delete_object(key: str) -> None:
    settings = _settings()
    if backend_name() == "s3":
        try:
            client().delete_object(Bucket=settings.s3_bucket, Key=key)
            return
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("S3 delete failed for %s: %s", key, exc)
    path = _fs_root() / key
    if path.is_file():
        path.unlink()


def public_url(key: str) -> str:
    """Client-facing URL for a stored object."""
    if not key:
        return ""
    base = _settings().s3_public_base_url.strip().rstrip("/")
    if base:
        return f"{base}/{key}"
    return f"/media/{key}"


def stats() -> dict[str, Any]:
    """Small diagnostic payload for the health endpoint."""
    return {
        "backend": backend_name(),
        "bucket": _settings().s3_bucket if backend_name() == "s3" else None,
        "public_base": _settings().s3_public_base_url or None,
    }
