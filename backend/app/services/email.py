"""Transactional email, sent through Resend.

Mirrors the integration used on taves-website: a single REST call to
``https://api.resend.com/emails`` with the API key in the ``Authorization``
header. No SDK, so there is nothing to keep in step with a provider release.

When ``RESEND_API_KEY`` is unset the service degrades to a no-op that logs what
it *would* have sent. That keeps local development, the offline demo and the
test suite independent of any external provider — the same "graceful fallback"
rule the rest of LocalIQ follows.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)

RESEND_ENDPOINT = "https://api.resend.com/emails"
TIMEOUT_S = 10.0


# ---------------------------------------------------------------------------
# Transport
# ---------------------------------------------------------------------------


def send_email(
    *,
    to: str,
    subject: str,
    text: str,
    html: str | None = None,
    reply_to: str | None = None,
) -> bool:
    """Send one email. Returns True when Resend accepted it.

    Never raises: the caller is a request handler, and a mail outage must not
    fail registration or a password reset.
    """
    settings = get_settings()
    api_key = settings.resend_api_key.strip()

    payload: dict[str, Any] = {
        "from": settings.resend_from,
        "to": [to],
        "subject": subject,
        "text": text,
    }
    if html:
        payload["html"] = html
    if reply_to:
        payload["reply_to"] = reply_to

    if not api_key:
        logger.info("Email disabled (no RESEND_API_KEY); skipping %r to %s", subject, to)
        return False

    try:
        with httpx.Client(timeout=TIMEOUT_S) as client:
            response = client.post(
                RESEND_ENDPOINT,
                json=payload,
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
            )
            response.raise_for_status()
        logger.info("Email sent (%s) to %s", subject, to)
        return True
    except Exception as exc:  # noqa: BLE001 - mail must never break the caller
        logger.warning("Resend send failed (%s to %s): %s", subject, to, exc)
        return False


# ---------------------------------------------------------------------------
# Links
# ---------------------------------------------------------------------------


def verification_link(token: str) -> str:
    return f"{get_settings().app_public_origin}/verify-email?token={token}"


def password_reset_link(token: str) -> str:
    return f"{get_settings().app_public_origin}/reset-password?token={token}"


# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------


def _greeting(name: str | None) -> str:
    return f"Hello {name}," if name else "Hello,"


def send_verification_email(*, to: str, name: str | None, token: str) -> bool:
    """Ask the account owner to confirm their address."""
    link = verification_link(token)
    hours = get_settings().email_verification_ttl_hours
    text = "\n".join(
        [
            _greeting(name),
            "",
            "Welcome to LocalIQ. Confirm this email address so your account and "
            "taste profile are tied to you:",
            "",
            link,
            "",
            f"The link is valid for {hours} hours. If you did not create an "
            "account, you can ignore this message.",
            "",
            "— LocalIQ",
        ]
    )
    html = _wrap(
        _greeting(name),
        "Welcome to LocalIQ. Confirm this email address so your account and taste "
        "profile are tied to you.",
        link,
        "Confirm my email",
        f"The link is valid for {hours} hours. If you did not create an account, "
        "you can ignore this message.",
    )
    return send_email(to=to, subject="Confirm your LocalIQ email", text=text, html=html)


def send_password_reset_email(*, to: str, name: str | None, token: str) -> bool:
    """Send a single-use password reset link."""
    link = password_reset_link(token)
    text = "\n".join(
        [
            _greeting(name),
            "",
            "Use this link to choose a new LocalIQ password:",
            "",
            link,
            "",
            "The link is valid for 30 minutes and can only be used once. If you "
            "did not ask for this, you can safely ignore it.",
            "",
            "— LocalIQ",
        ]
    )
    html = _wrap(
        _greeting(name),
        "Use the button below to choose a new LocalIQ password.",
        link,
        "Reset my password",
        "The link is valid for 30 minutes and can only be used once. If you did "
        "not ask for this, you can safely ignore it.",
    )
    return send_email(to=to, subject="Reset your LocalIQ password", text=text, html=html)


def _wrap(greeting: str, body: str, link: str, cta: str, foot: str) -> str:
    """Small, dependency-free HTML email (inline styles only)."""
    return f"""\
<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;line-height:1.5;color:#2b2b2b;max-width:520px">
  <p style="font-size:16px;margin:0 0 12px">{greeting}</p>
  <p style="font-size:15px;margin:0 0 18px">{body}</p>
  <p style="margin:0 0 22px">
    <a href="{link}" style="background:#FF5A36;color:#fff;text-decoration:none;padding:12px 20px;border-radius:10px;font-weight:600;display:inline-block">{cta}</a>
  </p>
  <p style="font-size:13px;color:#6b6b6b;margin:0 0 8px">{foot}</p>
  <p style="font-size:12px;color:#9a9a9a;margin:0;word-break:break-all">{link}</p>
</div>"""
