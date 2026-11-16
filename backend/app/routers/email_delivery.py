"""Signed Supabase Auth email hook -> the configured transactional relay.

No admin/service-role key is needed. Link destinations are server-controlled;
user-selected redirect URLs and editable user metadata cannot change them.
Raw payloads, OTPs, tokens, addresses and provider credentials are never logged
or stored in domain records. Only a webhook digest/receipt is kept for deduplication.
"""

from datetime import datetime, timezone
import hashlib
from html import escape
import re
from urllib.parse import urlencode

from fastapi import APIRouter, HTTPException, Request
import httpx
from standardwebhooks import Webhook
from standardwebhooks.webhooks import WebhookVerificationError
from starlette.concurrency import run_in_threadpool

from app import config
from app.storage import STORE_LOCK, read_json, write_json

router = APIRouter(tags=["Auth email delivery"])
MAX_BODY = 65536
LINK_ACTIONS = {
    "signup": ("Confirm your email", "Confirm email"),
    "recovery": ("Reset your password", "Reset password"),
    "invite": ("Your BrandGuard invitation", "Accept invitation"),
    "magiclink": ("Your BrandGuard sign-in link", "Sign in"),
}
NOTICES = {
    "password_changed_notification": "Your account password was changed.",
    "email_changed_notification": "Your account email address was changed.",
    "phone_changed_notification": "Your account phone number was changed.",
    "identity_linked_notification": "A sign-in identity was added to your account.",
    "identity_unlinked_notification": "A sign-in identity was removed from your account.",
    "mfa_factor_enrolled_notification": "An authentication factor was added to your account.",
    "mfa_factor_unenrolled_notification": "An authentication factor was removed from your account.",
}


def email_content(payload):
    user = payload.get("user")
    data = payload.get("email_data")
    if not isinstance(user, dict) or not isinstance(data, dict):
        raise HTTPException(400, "Invalid email-hook payload")
    recipient = user.get("email")
    if (
        not isinstance(recipient, str)
        or not re.fullmatch(r"[^\s@]{1,200}@[^\s@]{1,200}\.[^\s@]{1,60}", recipient)
        or len(recipient) > 254
    ):
        raise HTTPException(400, "Invalid email recipient")
    action = data.get("email_action_type")
    if action in LINK_ACTIONS:
        token = data.get("token_hash")
        if not isinstance(token, str) or not re.fullmatch(
            r"[A-Za-z0-9_-]{16,512}", token
        ):
            raise HTTPException(400, "Invalid verification token")
        target = (
            config.AUTH_REDIRECT_URL
            if action in {"recovery", "invite"}
            else config.PUBLIC_APP_URL + "/auth/confirm"
        )
        if not target.startswith("https://") or not config.SUPABASE_URL.startswith(
            "https://"
        ):
            raise HTTPException(503, "Secure auth callback is not configured")
        link = (
            config.SUPABASE_URL
            + "/auth/v1/verify?"
            + urlencode({"token": token, "type": action, "redirect_to": target})
        )
        subject, button = LINK_ACTIONS[action]
        body = (
            f"<h1>{escape(subject)}</h1><p>Continue securely with BrandGuard.</p>"
            f'<p><a href="{escape(link, quote=True)}">{escape(button)}</a></p>'
            "<p>This link expires. If you did not request it, you can ignore this email.</p>"
        )
    elif action == "reauthentication":
        token = data.get("token")
        if not isinstance(token, str) or not re.fullmatch(r"[0-9]{4,10}", token):
            raise HTTPException(400, "Invalid reauthentication code")
        subject = "Your verification code"
        body = f"<h1>BrandGuard verification</h1><p>Your code is <strong>{escape(token)}</strong>.</p>"
    elif action in NOTICES:
        subject = "Account security notification"
        body = f"<h1>BrandGuard security</h1><p>{escape(NOTICES[action])}</p>"
    else:
        # Email-change double confirmation needs its own explicit implementation.
        raise HTTPException(
            400, "This email action is not supported by this application"
        )
    html = (
        '<!doctype html><html><body style="font:16px system-ui;color:#142c3b;padding:24px">'
        + body
        + "<p>BrandGuard — human review remains required for publication.</p></body></html>"
    )
    return {
        "from": config.EMAIL_FROM,
        "to": [recipient],
        "subject": "BrandGuard — " + subject,
        "html": html,
    }


@router.post("/api/v1/auth/hooks/email", include_in_schema=False)
async def send_auth_email(request: Request):
    secret = config.SUPABASE_EMAIL_HOOK_SECRET
    if (
        not secret
        or not config.RESEND_API_KEY
        or not config.RESEND_API_URL.startswith("https://")
        or not config.EMAIL_FROM
    ):
        raise HTTPException(503, "Transactional auth email is not configured")
    raw = bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw) > MAX_BODY:
            raise HTTPException(413, "Email-hook payload is too large")
    try:
        payload = Webhook(secret.removeprefix("v1,")).verify(
            bytes(raw), dict(request.headers)
        )
    except (WebhookVerificationError, ValueError, TypeError):
        raise HTTPException(401, "Invalid or expired webhook signature") from None
    if not isinstance(payload, dict):
        raise HTTPException(400, "Invalid email-hook payload")
    message = email_content(payload)
    identifier = (
        "supabase-email:"
        + hashlib.sha256(request.headers["webhook-id"].encode()).hexdigest()
    )
    return await run_in_threadpool(deliver_once, message, identifier)


def deliver_once(message, identifier):
    """Keep synchronous SQL/network work off the HTTP event loop."""
    path = config.DATA_DIR / "auth_email_events.json"
    # Serialize the short relay call so concurrent delivery retries share a receipt.
    # Provider idempotency additionally covers an accepted send followed by DB failure.
    with STORE_LOCK:
        receipts = read_json(path, [])
        if any(row["id"] == identifier for row in receipts):
            return {}
        try:
            response = httpx.post(
                config.RESEND_API_URL.rstrip("/") + "/emails",
                headers={
                    "Authorization": "Bearer " + config.RESEND_API_KEY,
                    "Idempotency-Key": identifier,
                    "Content-Type": "application/json",
                },
                json=message,
                timeout=2.5,
            )
            response.raise_for_status()
            result = response.json()
            receipt = result.get("id") if isinstance(result, dict) else None
            if not isinstance(receipt, str) or not receipt:
                raise ValueError("Relay returned no message receipt")
        except (httpx.HTTPError, ValueError, TypeError):
            raise HTTPException(
                503,
                "Auth email could not be accepted by the delivery service. Try later.",
            ) from None
        receipts.append(
            {
                "id": identifier,
                "message_id": receipt[:200],
                "sent_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        write_json(path, receipts[-1000:])
    return {}
