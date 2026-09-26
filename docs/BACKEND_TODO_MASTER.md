# LocalIQ — Backend Remaining Work

> **Scope:** What is genuinely still missing or unfinished on the backend so the
> Flutter app (`frontend_flutter`) is fully served by the FastAPI backend
> (`backend/`).
>
> **Re-audited:** 2026-09-27 against the running backend. This document was
> originally a pre-sprint audit; most of what it listed as missing has since been
> built. Stale items have been removed rather than left to mislead.
>
> **Legend:** 🔴 Blocker · 🟠 High · 🟡 Medium · ⚪ Cleanup

---

## STATUS — updated 2026-09-27

Verified against a running backend: **384 passed, 1 skipped**. Flutter
`analyze`: no issues. The Postgres/Docker deployment boots the full migration
chain and serves the tunnel.

### Shipped

| Ref | Item | Where it lives |
|---|---|---|
| §1.1–1.6 | `GET /places`, `/places/{id}`, `/{id}/experiences`, `/popular`, `/gems`, `/discover` | `api/v1/place_discovery.py` + `services/places.py` (a `Place` is synthesised over `Experience`; no separate table) |
| §1.7 / §1.8 | `/traffic`, `/context/live` | `services/context.py` — honest IST hour-of-day heuristic, not a live feed |
| §1.9–1.11 | `/auth/refresh`, `/auth/guest`, `/auth/forgot-password`, `/auth/reset-password` | `api/v1/auth.py`, `services/auth.py` (rotating refresh tokens) |
| §1.12 | `/auth/google` | tokeninfo verification with a dev-mode fallback. **App side still missing** (see Remaining) |
| §2.1 / §2.2 | Place shape + app Experience fields | `schemas.py` (`title/placeId/tagline/activityMinutes/typicalSpend/localScore/touristScore/highlights/bookingNote/weatherSuitability/practicalTip`) |
| §2.4 | Saved experiences | `api/v1/favorites.py` — `GET/POST/DELETE /me/favorites` |
| §2.7 / §7.1 | Alembic migrations | `backend/alembic/` (20 revisions); boots on pgvector Postgres |
| §3.1 | Token never attached | `AuthTokenHolder` → `JsonApiClient.tokenProvider`, plus multipart support |
| §3.2 / §3.3 | Cold-start restore, server-side logout | `POST /auth/refresh` on startup; `POST /auth/logout` revokes the session |
| §3.4 | Rate limiting + lockout | `rate_limit.py` (slowapi) and `services/lockout.py`, wired into `/auth/login` |
| §3.5 | Signing-key guard | `config.py` refuses to boot in production/staging with the dev default |
| §3.6 | Email verification + account deletion | `services/email.py` (Resend, no SDK), `services/verification.py`, `DELETE /auth/me` + `services/account.py` |
| §4.1 | Guides marketplace | `api/v1/guides.py` wired; `guides_ops.py` adds availability, bookings, training |
| §4.4 / §4.5 | Quests, wallet | `api/v1/quests.py`, `api/v1/wallet.py` |
| §4.9 | Booking state machine | `POST /guide-bookings/{id}/transition` + rules in `services/journey_rules.py`; legacy requests no longer claim `confirmed_mock` |
| §4.12 | Admin surface | `api/v1/admin.py` (content CRUD, candidate approve/reject) behind `ADMIN_API_KEY` |
| §4.3 / §4.6 | Social + trust | `api/v1/meetup.py`, `groups.py`, `trust.py` |
| §5.1 | Empty images | 107/234 experiences have self-hosted photos; `/static/images` + `/media/*` routed through Caddy |
| §7.2 | Test hermeticity | `tests/conftest.py` — per-test DB, no real network, no real email |
| §7.11 | `LOCALIQ_OFFLINE` default | now `false` (backend-first) |
| §11.1 / §11.2 | Both shape mismatches | fixed |
| — | Maps, onboarding, driver trips | interactive vector map, taste-chat onboarding, guide onboarding, `/driver/trips*` |

---

## Remaining

Only these are actually open.

### 1. Notifications (§4.10) 🔴
There is no notifications table or endpoint, and no push integration.

- [ ] `notifications` table (`user_id`, `kind`, `title`, `body`, `read_at`, `created_at`)
- [ ] `GET /notifications`, `POST /notifications/{id}/read`, unread count
- [ ] Emit one on booking transitions and guide verification
- [ ] Push (FCM) if time, otherwise in-app polling

### 2. Phone / OTP (§4.11) 🟡
`User` has no `phone` column and there is no OTP flow. Optional, but common in a
demo.

- [ ] `phone` column + verification state
- [ ] `POST /auth/otp/request`, `POST /auth/otp/verify` (Twilio, or stubbed locally)

### 3. Payments are still simulated 🟠
The booking lifecycle is real, but `payment_status` is mocked and no money moves.

- [ ] Decide: integrate a provider (Razorpay is the natural fit for India) or
      rename the field to make the simulation explicit in the API contract

### 4. App-side wiring 🟠
Backend endpoints exist; the Flutter app does not call some of them.

- [ ] `restore()` at app start (calls `POST /auth/refresh`)
- [ ] `signOut()` calls `POST /auth/logout`
- [ ] `google_sign_in` package supplying an `idToken` to `POST /auth/google` —
      the button throws today

### 5. App-side contract tests (§8) 🟠
`routes_test.dart` and `domain_test.dart` run against the local dataset. No test
touches `JsonApiClient`, `RemoteAuthService`, `RemotePlaceRepository` or
`RemoteContextRepository`, which is what allowed the original app/backend drift.

- [ ] Add typed contract tests that hit the real backend shapes

### 6. Documentation ⚪
- [ ] `frontend_flutter/docs/BACKEND_CONTRACT.md` is stale: it lists `GET /auth/me`
      and `POST /auth/logout` as consumed, omits `/places/*`, `/traffic`,
      `/context/live`, and does not mention the Resend flow, email verification,
      account deletion or the driver endpoints
- [ ] Document `AUTH_SECRET_KEY` as a hard production requirement (done in
      `.env.example`, worth repeating in the deploy runbook)
- [ ] Add curl examples for the newer endpoints

---

## Why this list is short

The original audit assumed the app and backend shared almost nothing. That gap
has been closed: place-first discovery, live context, rotating auth, guest
sessions, email verification, maps, onboarding and driver trips are all built
and covered by the suite. What remains is genuinely peripheral — notifications,
telephony, real payments, and finishing the app-side wiring.
