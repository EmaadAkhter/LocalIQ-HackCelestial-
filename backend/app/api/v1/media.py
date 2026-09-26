"""Serve stored media objects (S3 or filesystem fallback).

Clients use the URLs produced by ``storage.public_url``; when no public CDN
base is configured this proxy streams the bytes, so the Flutter app never needs
S3 credentials.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, Response

from app.rate_limit import PUBLIC_LIMIT, limiter
from app.services import storage

router = APIRouter()


@router.get("/media/{key:path}", summary="Serve a stored media object")
@limiter.limit(PUBLIC_LIMIT)
def serve_media(request: Request, response: Response, key: str):
    obj = storage.get_object(key)
    if obj is None:
        raise HTTPException(status_code=404, detail="Media not found")
    data, content_type = obj
    return Response(
        content=data,
        media_type=content_type,
        headers={"Cache-Control": "public, max-age=86400"},
    )


@router.get("/storage/status", summary="Object storage backend status")
@limiter.limit(PUBLIC_LIMIT)
def storage_status(request: Request, response: Response):
    return storage.stats()
