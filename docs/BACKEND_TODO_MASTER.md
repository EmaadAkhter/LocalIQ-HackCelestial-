# LocalIQ — Backend Remaining Work (Master Checklist)

> **Scope:** Every piece of work that is *missing or broken on the backend side*
> to make the Flutter app (`frontend_flutter`) fully functional against the
> FastAPI backend (`backend/`).
>
> **Audited:** full backend tree + full `lib/` tree of the Flutter app + the
> existing `frontend_flutter/docs/BACKEND_CONTRACT.md`.
>
> **Legend:** 🔴 Blocker · 🟠 High · 🟡 Medium · ⚪ Cleanup · ✅ Already done

---

## STATUS — updated 2026-09-27

Sprints 1–3 of §10 are largely closed. Verified against a running backend
(`362 passed, 1 skipped`) and the Flutter app (`flutter analyze`: no issues).

**Closed since this audit**

| Ref | Item | Where it lives now |
|---|---|---|
| §1.1–1.6 | `GET /places`, `/places/{id}`, `/{id}/experiences`, `/popular`, `/gems`, `/discover` | `backend/app/api/v1/place_discovery.py` + `services/places.py` (Place synthesised over `Experience`, no new table) |
| §1.7 / §1.8 | `/traffic`, `/context/live` | `services/context.py` (honest ist-hour heuristic + area nudge); weather cache already present (§6.7 ✅) |
| §1.9–1.11 | `/auth/refresh`, `/auth/guest`, `/auth/forgot-password` (+ `/auth/reset-password`) | `api/v1/auth.py`, `services/auth.py` (rotating refresh tokens) |
| §1.12 | `/auth/google` | tokeninfo verify with a dev-mode fallback; the **app** still needs `google_sign_in` to supply an idToken |
| §2.1 / §2.2 | Place shape, Experience app fields | `schemas.py` (`Place` projection + `title/placeId/tagline/activityMinutes/typicalSpend/localScore/touristScore/highlights/bookingNote/weatherSuitability/practicalTip`) |
| §2.7 / §7.1 | Alembic migrations | `backend/alembic/` (18 revisions); dev DB stamped at head |
| §3.1 | **Token never attached** | `AuthTokenHolder` → `JsonApiClient.tokenProvider` (access token sent on every request) |
| §5.1 | Empty images | 107/234 experiences have self-hosted photos (scraper photo enrichment); `image_key` → `/media/*` |
| §7.11 | `LOCALIQ_OFFLINE` default | now `false` (backend-first) |
| §11.1 / §11.2 | Both shape mismatches | fixed |
| §3.6 | **Email verification** | `services/email.py` (Resend, no SDK) + `services/verification.py`: `users.email_verified`, `POST /auth/verify-email`, `POST /auth/resend-verification`, and `forgot-password` now actually emails the reset link |
| §7.x | Docker/Postgres deployment | migrations now boot on pgvector Postgres (PKs, boolean defaults, `CREATE EXTENSION vector`); Caddy routes `/static/*` + `/media/*`; `PUBLIC_BASE_URL` for device-reachable photo URLs |
| — | **New** | Driver trip map (`/driver/trips*`, `bookings/{id}/tracking`) + guided onboarding (taste chat, guide onboarding) |

**Still open**

- §3.2 `restore()` is still not called at app start; §3.3 `signOut()` does not hit `/auth/logout`.
- §3.4 rate limiting on login, §3.5 `AUTH_SECRET_KEY` production guard.
- §2.4 saved, §4.x product backends (wallet/quests/safety/social), §4.10 notifications, §4.12 admin.
- §3.6 **account deletion** (email verification is done; deletion is not).
- §8 app-side contract tests.
- §1.12 app-side `google_sign_in`.

---

## 0. THE HEADLINE PROBLEM 🔴

**The Flutter app and the backend currently share almost nothing.**

| Metric | Count |
|---|---|
| Backend routes total | 16 |
| Backend routes the app actually calls | **2** (`POST /auth/login`, `POST /auth/register`) |
| Backend routes called but **shape-broken** | 2 (`GET /experiences/{id}`, `GET /weather`) |
| Backend routes **nobody calls** | **11** (the whole product) |
| Endpoints the app calls that the backend **does not have** | **11** |
| Default runtime mode of the app | `LOCALIQ_OFFLINE=true` → **100% local dataset** |

The backend's two crown jewels —

- `POST /api/v1/recommend` (the 459-line feasibility + ranking engine)
- `POST /api/v1/parse` + `POST /api/v1/chat` (the Ollama NL layer)

— are **never called by the app**. Meanwhile the app's entire discovery model
(`Place → Experience`, `FeasibilityTier`, `traffic`, `popular/gems/discover`)
**has no backend at all**.

The demo you see today is `LocalPlaceRepository` (16 places) +
`LocalContextRepository` (fake weather) + a client-side `FeasibilityEngine`.
The backend is a separate, better product that nothing is plugged into.

**There are exactly 3 things that can happen. Pick one:**

| Option | What it means | Effort |
|---|---|---|
| **A. Backend chases the app** (recommended) | Build the 11 missing endpoints + fix the 2 broken shapes | ~4–6 days |
| **B. App chases the backend** | Rewrite the app to call `/recommend`, `/experiences`, `/chat` | ~5–7 days, throws away `Place` model + FeasibilityTier |
| **C. Claim backend-only demo** | Judge the backend via `/docs` / Swagger, keep the app offline | 0 days, but the "full-stack" claim is hollow |

Everything below assumes **Option A**.

---

## 1. ENDPOINT GAPS — What the app calls that does not exist 🔴

Base URL prefix: app uses `.../api/v1` (`core/config/environment.dart:25-30`),
so all paths below are relative to `/api/v1`.

### 1.1 `GET /places` — the main discovery list 🔴
- **Called by:** `features/places/data/remote_place_repository.dart:24-27`
- **Query params sent:** `text`, `lat`, `lng`, `radius_km`, `limit`, `categories` (repeated key), `open_at`, `max_spend`
- **Expected response:** `Place[]` (see §2.1 for the required shape)
- **Backend has instead:** `GET /api/v1/experiences` (`app/api/v1/experiences.py:16`) which accepts `category`, `q`, `min_rating`, `limit`, `offset` — **no geo, no text-vs-radius search, no budget/time filters**.
- **Work:**
  - [ ] New router `app/api/v1/places.py`
  - [ ] Add `Place` table (or synthesise a place view over experiences) — see §2.1
  - [ ] Implement `text` fuzzy match (reuse `recommender.resolve_location()` for lat/lng text, and a name/description LIKE for the rest)
  - [ ] Implement `radius_km` filter via `recommender.haversine_km()` (`services/recommender.py:67`)
  - [ ] Implement `categories` multi-value filter
  - [ ] Implement `open_at` filter via `recommender.is_open_at()` (`services/recommender.py:135`)
  - [ ] Implement `max_spend` filter on `avg_cost`
  - [ ] Keep `limit`/`offset` paging consistent with the existing experiences router
- **Files to touch:** new `app/api/v1/places.py`, `app/main.py:63-69` (register), `app/models.py` (Place), `app/schemas.py`, `app/seed.py` + `backend/data/mumbai_experiences.json`

### 1.2 `GET /places/{id}` — place detail 🔴
- **Called by:** `remote_place_repository.dart:38`
- **Needs:** 404 → `null` (not an exception) — the app maps 404 to null at `:40-42`
- **Work:** fetch place + aggregate its experiences + rating rollup

### 1.3 `GET /places/{id}/experiences` — the list of things to do at a place 🔴
- **Called by:** `remote_place_repository.dart:48`
- **This is the `Place → Experience` child collection.** The backend has the
  **exact inverse** (`GET /experiences/{id}/guides`, `experiences.py:59`) and no
  `place_id` foreign key at all in `models.py:9-31`.
- **Work:**
  - [ ] Add `place_id` FK on `Experience` (`app/models.py:9-31`)
  - [ ] Backfill from `data/mumbai_experiences.json` (needs a venue field in the dataset)
  - [ ] New endpoint returning the child `Experience[]`

### 1.4 `GET /places/popular` — "popular near me" 🔴
- **Called by:** `remote_place_repository.dart:73-81` (defaults: 6 km radius, 12 results)
- **Query:** `lat`, `lng`, `radius_km`, `limit`
- **Work:** rank by `rating × review_weight` within radius. The backend has **no `review_count` column** — add it or proxy with `rating` alone.

### 1.5 `GET /places/gems` — local-gem rail 🟠
- **Called by:** `remote_place_repository.dart:91-99` (defaults: 8 km, 12)
- **Backend already has the data:** `Experience.local_gem_score` 0.0–1.0 (`models.py:30`), currently only used inside `score_experience()` (`recommender.py:291-357`).
- **Work:** trivial — filter `local_gem_score >= 0.7` within radius, sort desc. ~30 lines.

### 1.6 `GET /places/discover` — NL search 🟠
- **Called by:** `remote_place_repository.dart:105-122`
- **Expected response:** `{ places: [...], experiences: [...], interpreted_query: {...} }`
- **Backend has the brain already:** `POST /api/v1/parse` (`app/api/v1/parse.py:144`) returns `ParsedConstraints` and `services/parser.py` has a full keyword/regex extractor (currently **dead code**, see §6.1).
- **Work:**
  - [ ] Wrap `parse_constraints` / `heuristic_parse` into a GET handler
  - [ ] Feed the parsed constraints into `recommender.recommend()`
  - [ ] Return the 3-key envelope the app expects
  - [ ] Decide: keep `GET /places/discover` as the single entry, or have the app call `POST /parse` + `POST /recommend` separately (simpler for the backend, worse for the app)

### 1.7 `GET /traffic` 🟠
- **Called by:** `features/context/data/remote_context_repository.dart:26-30`
- **Expected:** `{ traffic: { level, speed_multiplier, updated_at } }` or flat
- **App enums:** `TrafficLevel` (`context_models.dart:255-274`) — the app currently fakes it from the clock (`local_context_repository.dart:53-71`).
- **Work:**
  - [ ] Decide a real source: Google Traffic API / TomTom / Mapbox. **No SDK in `requirements.txt` today.**
  - [ ] Or: a cheap heuristic (hour-of-day × area) and be honest in the docstring that it is synthetic
  - [ ] Cache it (`services/weather.py` has no cache today — add one while you're there)

### 1.8 `GET /context/live` — one call for weather + traffic 🟠
- **Called by:** `remote_context_repository.dart:37-50`
- **Expected:** `{ weather: {...}, traffic: {...} }`
- **Work:** compose `fetch_weather()` (`services/weather.py:50`) + the new traffic service. This is the app's main "right now" banner (`explorer/home/.../right_now_banner.dart`).

### 1.9 `POST /auth/refresh` 🔴
- **Called by:** `remote_auth_service.dart:49-52` (from `restore()`)
- **Backend has no refresh endpoint.** `services/auth.py` issues a single opaque token with a 7-day TTL (`config.py:25`).
- **Work:**
  - [ ] `RefreshToken` table (`user_id`, `token_hash`, `expires_at`, `revoked`)
  - [ ] Issue a refresh token alongside the access token on register/login
  - [ ] Endpoint rotates the pair
  - [ ] Shorten access-token TTL to ~15–30 min so refresh is actually used

### 1.10 `POST /auth/guest` 🟠
- **Called by:** `welcome_screen.dart:130`, `login_screen.dart:260`, `signup_screen.dart:234` — **this is the app's default first-run path.**
- **Expected:** returns a full `AuthSession` so the app can be used logged-out.
- **Work:**
  - [ ] Create a real `User` row with `is_anonymous=true` (column does not exist — add it)
  - [ ] Return the same session envelope
  - [ ] Ban anonymous users from bookings/writes later (or allow, decide)

### 1.11 `POST /auth/forgot-password` 🟠
- **Called by:** `forgot_password_screen.dart:41` and a hardcoded debug button at `profile_screen.dart:353-364`
- **No email service exists at all** — zero SendGrid/SES/SMTP code in the repo.
- **Work:**
  - [ ] `PasswordResetToken` table
  - [ ] Email sender (or, for the demo, return the reset link in the response **only** when `APP_ENV=development` — be loud about it)
  - [ ] `POST /auth/reset-password` to consume it
  - [ ] Delete/relabel the hardcoded debug button

### 1.12 `POST /auth/google` 🟡
- **Called by:** `login_screen.dart:248`, `signup_screen.dart:222` — but with **no `idToken` argument**, so `remote_auth_service.dart:83-87` throws `ConfigurationException` every time. Google sign-in is 100% non-functional today.
- **Work:**
  - [ ] Add `google_sign_in` to the app (not backend work, but the button is user-visible so it must be listed)
  - [ ] Backend: verify the Google ID token (`google-auth` lib), upsert user by `sub`
  - [ ] **OR** just delete the button. Cheapest honest fix.

---

## 2. DATA-MODEL GAPS

### 2.1 The `Place` entity does not exist 🔴
The app's core model is `Place → Experience` (1:N). The backend has a **flat
`Experience` table** and no venue/place concept at all.

Backend `Experience` (`app/models.py:9-31`) has 15 columns. App `Place`
(`features/places/domain/place.dart:10-114`) has 20 fields. **Mapping:**

| App `Place` field | Backend equivalent | Status |
|---|---|---|
| `id` | `Experience.id` (int) | ⚠️ stringification needed |
| `name` | `Experience.name` | ✅ |
| `category` | `Experience.category` (str) | ⚠️ str → enum |
| `address` | — | ❌ **missing** |
| `area` | — | ❌ **missing** (dataset has no area field) |
| `centre` (GeoPoint) | `lat` + `lng` | ⚠️ nested object |
| `heroImageUrl` | `image_url` | ⚠️ empty `""` for every row — see §5.1 |
| `imageUrls[]` | — | ❌ **missing** (no gallery) |
| `openingHours` (per weekday) | `open_time` / `close_time` (2 strings) | ❌ **needs per-weekday expansion** |
| `accessibility` | `accessibility_flags` (JSON) | ⚠️ shape differs |
| `rating` | `rating` | ✅ |
| `reviewCount` | — | ❌ **missing** |
| `priceLevel` (0–4) | — | ❌ **missing** (only `avg_cost` int) |
| `typicalSpend` | `avg_cost` | ✅ |
| `crowdLevel` | — | ❌ **missing** |
| `indoor` (bool) | `indoor_outdoor` (str) | ⚠️ str → bool |
| `localFavourite` | `local_gem_score > 0.7` | ✅ derivable |
| `bookingRequired` | — | ❌ **missing** |
| `phone` | — | ❌ **missing** |
| `website` | — | ❌ **missing** |
| `summary` | `description` | ✅ |

**Work:**
- [ ] Decide: new `places` table, or synthesise a place view from experiences grouped by (name, area)
- [ ] Add the ❌ columns
- [ ] Add an area field to the seed dataset
- [ ] Add per-weekday hours (`opening_hours` JSON) replacing `open_time`/`close_time`

### 2.2 `Experience` app model needs 6 new backend fields 🟠
App `Experience` (`place.dart:166-272`) vs backend `Experience`:

| App field | Status |
|---|---|
| `tagline` | ❌ missing |
| `secondaryCategory` | ❌ missing |
| `weatherSuitability` (`WeatherSuitability` enum) | ❌ missing — backend has raw `indoor_outdoor` only |
| `bookingNote` | ❌ missing |
| `touristScore` (0–100) | ❌ **missing — the "local vs tourist" axis the whole product ranks on** |
| `highlights[]` | ❌ missing |
| `practicalTip` | ❌ missing |
| `localScore` 0–100 | ⚠️ backend has 0.0–1.0 — needs ×100 rescale |

**`touristScore` is the highest-value one.** The backend ranks on
`local_gem_score` only (`recommender.py:291-357`); the app ranks on a
local↔tourist axis. Without it the two rankers disagree.

### 2.3 `Itinerary` + `ItineraryStop` tables are dead ⚪
- `app/models.py:99-126` defines both, docstring literally says *"hackathon-optional"*.
- **No endpoint touches them.** No CRUD, no read, no write.
- The app's `ItineraryRepository` doc-comment (`itinerary_repository.dart:5`) already sketches `POST /itineraries/{id}/stops` and `PATCH .../reorder`.
- **Work:** either wire them up (§1.3 / new §1.x) or delete them. Right now they are schema debt that lies to judges.
- Also: `itineraryRepositoryProvider` (`core/providers.dart:155-162`) is hardcoded to `LocalItineraryRepository` — **there is no remote branch at all.**

### 2.4 `Saved` has no backend home 🔴
- App: `savedRepositoryProvider` (`core/providers.dart:166-168`) → always `LocalSavedRepository`.
- App model `SavedExperience` (`recommendation.dart:266-303`) has a `fromJson` — it was designed for a server.
- **Work:** new `saved` table (`user_id`, `experience_id`, `collection`, `note`, `saved_at`, unique(user, experience)) + `GET/POST/DELETE /saved`.

### 2.5 `User.group_type` is never written ⚪
- `app/models.py:60` declares it. Nothing in the codebase sets or reads it.
- The app's `DiscoveryContext` has a `GroupType` enum (`context_models.dart:63-83`) and sends it nowhere.
- **Work:** either persist it from `/auth/register` or delete the column.

### 2.6 `chat` has no persistence 🟡
- `app/api/v1/chat.py:71` is stateless. `ChatThread` / `ChatMessage` exist in the app (`assistant/domain/chat_message.dart:33-162`) with `fromJson` already written.
- **Work:** `chat_threads` + `chat_messages` tables, or accept statelessness explicitly and delete the app-side models.

### 2.7 No migrations 🟠
- `alembic==1.20.0` is in `requirements.txt` but there is **no `alembic.ini`, no `migrations/`**.
- `database.py:72` uses `SQLModel.metadata.create_all(engine)` — schema changes are destructive/manual.
- **Work:** `alembic init`, generate the initial revision, wire `alembic upgrade head` into the Dockerfile entrypoint. Judges will ask.

---

## 3. AUTH GAPS

### 3.1 The app never attaches the access token 🔴🔴 — **the single worst bug**
- `JsonApiClient._applyHeaders()` (`core/network/json_api_client.dart:32-39`) sets `Authorization: Bearer` **only** from `env.apiKey` — a static build-time `--dart-define=LOCALIQ_API_KEY` string.
- `AuthSession.accessToken` (`auth_service.dart:30,36`, `remote_auth_service.dart:129`) is **never read by the client**. Grep confirms zero references in `json_api_client.dart`.
- **Consequence:** every authenticated endpoint 401s, or worse, the wrong token is sent. `/guides/me/requests`, `/saved`, any future `/users/me` will fail.
- **Work:** token-aware client — inject a `tokenProvider`, add a 401 → refresh → retry interceptor. **This must be fixed before any auth-gated endpoint is worth building.**

### 3.2 `restore()` is never called 🔴
- `AuthService.restore()` (`auth_service.dart:57`) → `POST /auth/refresh`.
- **Zero call sites in the app.** Session does not survive an app restart.
- `authSessionProvider` (`core/providers.dart:112`) is a `StreamProvider` that **no widget ever watches**. Only `currentUserProvider` is read.
- **Work:** call `restore()` in a bootstrap provider at app start; make the router react to session state.

### 3.3 `signOut()` does not call the backend 🟠
- `remote_auth_service.dart:95-98` only clears the local refresh token.
- Backend **does** have `POST /auth/logout` (`app/api/v1/auth.py:77`) that revokes the session row. Nobody calls it.
- **Consequence:** sessions stay valid on the server for 7 days after "logout".
- **Work:** one line. Do it.

### 3.4 No rate limiting / lockout 🟠
- `services/auth.py` has none. PBKDF2 at 200k iterations (`auth.py:26`) is the only cost.
- **Work:** simple in-process or Redis token-bucket on `/auth/login` + `/auth/register`. Return generic 401 (already correct — `auth.py:60` does not enumerate users).

### 3.5 `AUTH_SECRET_KEY` ships a default 🔴
- `config.py:24` → `localiq-dev-secret-change-me`. If it is not overridden in production, every session token hash is forgeable.
- **Work:** fail fast at boot if `APP_ENV != development` and the secret is still the default.

### 3.6 No email verification / no account deletion 🔴 (GDPR-ish, judges ask)
- **Work:** `email_verified` column + verify endpoint, or explicitly document the omission.

---

## 4. MISSING PRODUCT BACKENDS

The Flutter app has **6 whole features with zero data layer** — every screen is
static widget data. Each is a ready-made backend namespace.

| # | App screen | App data today | Backend | Work |
|---|---|---|---|---|
| 4.1 | `/guides` `guide_marketplace_screen.dart` | `_sampleGuides` — 3 hardcoded objects (`:20-95`) | **Partially exists!** `GET /guides` + `POST /guides/{id}/request` (`app/api/v1/guides.py:18,49`) | 🔴 Just **wire the app** to the existing endpoints. Cheapest win in this whole doc. |
| 4.2 | `/guide/dashboard` `guide_dashboard_screen.dart` | 100% static | ❌ none | 🟠 Guide-side: availability slots, incoming requests, earnings. App model `GuideAvailabilitySlot` (`models/guide.dart`) already exists. |
| 4.3 | `/people` `people_screen_screen.dart` | `_sampleMatches` — hardcoded (`:34-96`) | ❌ none | 🟠 Social matching. App model `PeopleMatch` (`models/social.dart`) exists. Needs a real matching endpoint. |
| 4.4 | `/quests` `quests_screen.dart` | `_quests` static list (`:16`) | ❌ none | 🟡 App model `Quest`, `QuestStop`, `QuestReward`, `UserQuestProgress` (`models/quest.dart`) is fully designed. Just needs CRUD + progress. |
| 4.5 | `/wallet` `wallet_screen.dart` | 100% static | ❌ none | 🟠 App model `ExperienceWallet`, `ExperienceLog` (`models/social.dart`). Needs a ledger. |
| 4.6 | `/safety` `safety_screen.dart` | 100% static | ❌ none | 🟡 SOS endpoint, trusted contacts, live location share. |
| 4.7 | `/director` `director_screen.dart` | 100% static | ❌ none | 🟡 "AI director" — could be a thin layer over the existing `POST /recommend`. |
| 4.8 | `/profile`, `/taste-profile` | local only | ❌ none | 🟡 Persist `TasteProfile` (`models/taste_profile.dart`) — currently has **no `fromJson` at all**. |

### 4.9 Booking is a mock 🔴
- `app/api/v1/guides.py:93` returns `status="confirmed_mock"` and the literal string `"No payment taken."`
- `models.py:94` and `schemas.py:121` also hardcode `"confirmed_mock"`.
- `GET /guides/me/requests` (`guides.py:24`) **rebuilds the response as a synthesized message** (`:36-44`) and hardcodes `status` — it does not read the stored row.
- **Work:**
  - [ ] Real status state machine: `pending → confirmed → completed / cancelled / declined`
  - [ ] **Payment integration** (Razorpay is the obvious India choice) — or honestly rename the status to `requested`
  - [ ] Fix `guides.py:24-44` to return the actual stored `GuideRequest` row
  - [ ] Date conflict detection (a guide can only be booked once per slot)

### 4.10 No notifications 🔴
- Zero Firebase/FCM/SendGrid/SMTP code in the entire repo.
- **Work:** `notifications` table + `GET /notifications`, `POST /notifications/{id}/read`. Push via FCM if time, in-app polling if not.

### 4.11 No OTP / phone 🟡
- Zero Twilio references. `User` has no `phone` column.
- The app's `SignUpRequest` has no phone field either, so this is optional — but "OTP login" is the single most common hackathon-demo ask. ~4h with Twilio.

### 4.12 No admin surface 🔴
- **There is no `is_admin` / role column on `User`** (`models.py:51-63`) and no admin router.
- **Work:** `is_admin` column + `require_admin` dependency + `/api/v1/admin/*` (feature flag, content CRUD, request moderation, user list).

---

## 5. DATA & CONTENT GAPS

### 5.1 Every image URL is an empty string 🔴
- `Experience.image_url` (`models.py:26`) is `""` for **every** record in `backend/data/mumbai_experiences.json`.
- The app renders real Unsplash photos from its local dataset (`local_places.dart`, `local_experiences.dart`).
- **Consequence:** the moment the app switches to the backend, **every image breaks**. This is the most visible possible demo failure.
- **Work:**
  - [ ] Add real image URLs to the dataset (Unsplash/Pexels CDN links, free licence)
  - [ ] Add `image_urls[]` gallery field
  - [ ] Add an `app_image.dart` fallback on the app side (it has one — `shared/widgets/app_image.dart:34-49` — verify it triggers on empty)

### 5.2 Dataset is thin and single-city 🟠
- Only `mumbai_experiences.json`. `README.md:43` claims 48 experiences / 12 guides; `tests/test_backend.py:35-36` only asserts ≥40 / ≥5.
- `services/recommender.py:23-64` hardcodes `KNOWN_AREAS` — 41 Mumbai anchors only.
- The app hardcodes its centre to South Mumbai (`core/providers.dart:60-62`, `18.9322, 72.8316`).
- **Work:** expand the dataset, add area/address fields, consider a second city or make the area list data-driven.

### 5.3 No `Place` rows to seed 🟠
- See §2.1. `app/seed.py:46-94` only handles `experiences` + `guides`, and resolves guide→experience FKs **positionally** (`:85-94`, fragile — flagged in-code at `:80-82`).
- **Work:** extend `seed.py` for places; make FK resolution key-based, not positional.

### 5.4 `DEMO_MODE` is a dead flag ⚪
- `config.py:18` → read only in `services/parser.py:299` and `services/guide.py:70`, **both dead modules**. So `DEMO_MODE=true` currently does nothing.
- **Work:** wire it into the live path (`api/v1/parse.py`, `api/v1/chat.py`) or delete it.

---

## 6. DEAD CODE & DUPLICATION (cleanup, but judges read code)

### 6.1 `app/services/parser.py` — 309 lines, never imported ⚪
- Full NL extractor with LLM+regex merge. The live router uses `api/v1/parse.py:heuristic_parse()` instead.
- **This is the best-written piece of unused code in the repo.** It should be the implementation behind `/places/discover` (§1.6), not deleted.
- ⚠️ Contains a **bug if wired:** returns `source` values outside the live `ParsedConstraints` contract.

### 6.2 `app/services/guide.py` — 86 lines, never imported ⚪
- Would **500 if wired**: `answer()` dereferences `request.experience` unconditionally (`:71,73`) but `ChatRequest.experience` is optional (`schemas.py:255`); and it returns `source="llm"` which is **not in the `ChatResponse.source` Literal** (`schemas.py:268` allows only `ollama|canned`).
- **Work:** delete, or fix and adopt as the real chat path.

### 6.3 `app/services/explain.py` — 99 lines, never imported ⚪
- Its own docstring (`:4`) **falsely claims** *"The recommender calls `build_reasons` per candidate"*. It does not — `recommender.build_why_this_fits` is used instead.
- **Work:** delete, or fix the docstring and make the recommender actually use it.

### 6.4 Duplicate `ollama_api_key` in config ⚪
- `config.py:32` **and** `config.py:34` — same field declared twice.

### 6.5 Unused `google_maps_api_key` 🟠
- `config.py:38` + `.env.example:33`. **Zero code references.** README:32 says *"reserved for future routing"*.
- Meanwhile the app calls Google Routes **directly from the client** (`features/routing/data/google_routes_service.dart:18`) and hardcodes a returning `0` for distance (`:21-27`, comment: *"Replace with a Distance Matrix call when the key is present"*).
- **Work:** either move routing server-side (backend owns the key — better security posture) or delete the config var and document that routing is client-side.

### 6.6 `ChatRequest.experience` is accepted and ignored 🟡
- `api/v1/chat.py` never reads it, yet `schemas.py:49-60` (`ExperienceContext`) exists solely to feed dead `services/guide.py`.

### 6.7 Weather service has no cache 🟡
- `services/weather.py:50-94` hits Open-Meteo on **every** `POST /recommend`. Under demo load this will rate-limit.
- **Work:** add a TTL cache (60–300s keyed on rounded lat/lon). Easy win.

---

## 7. INFRA / OPS GAPS

| # | Gap | Severity | Fix |
|---|---|---|---|
| 7.1 | **No Alembic migrations** (see §2.7) | 🟠 | `alembic init` + `upgrade head` on boot |
| 7.2 | **No `conftest.py`** — `tests/__init__.py` is empty, tests hit the **real** SQLite file (`test_backend.py:17-22`) | 🟠 | `tmp_path` fixture, in-memory SQLite |
| 7.3 | `api_smoke.sh` checks only **2 of 16** endpoints (`:20-25`) | 🟡 | Cover all routes |
| 7.4 | `Dockerfile` uses `python:3.14-slim` but README says 3.11+ — untested combo | 🟡 | Pin and verify |
| 7.5 | **No CI** for the backend | 🟠 | GitHub Actions: pytest + smoke |
| 7.6 | `gateway/` (caddy/kong/nginx), `infra/k8s`, `infra/jenkins` exist — **unverified whether any are wired** | ⚪ | Verify or document as reference-only |
| 7.7 | `/health` (`main.py:72`) returns a hardcoded `{"status":"ok"}` — **never checks DB or LLM** | 🟡 | Add `/health/ready` probing DB + Ollama |
| 7.8 | No request logging / tracing / metrics | 🟡 | Add `request_id` middleware + basic timings |
| 7.9 | CORS defaults to `http://localhost:3000` only (`config.py:17`) — the Flutter **web** build will be blocked | 🟠 | Add the web origin, or `*` in dev |
| 7.10 | `backend/.env` does not exist; `.env.example:24` ships `OLLAMA_MODEL=` **empty** | 🟠 | Empty model ⇒ deterministic fallbacks only (`llm.py:45-46,81-83`) — the AI demo silently degrades to canned replies |
| 7.11 | No `.env` in the Flutter app either; `LOCALIQ_OFFLINE` defaults to `true` | 🔴 | The single most important line in the whole demo |

---

## 8. TEST GAPS

`backend/tests/test_backend.py` — 25 tests. Solid coverage of auth, seeding,
recommender units, parse/chat fallbacks.

**Missing backend tests:**
- [ ] `/api/v1/weather` endpoint (the service is tested, the route is not)
- [ ] `GET /api/v1/guides` list route
- [ ] CORS behaviour
- [ ] Concurrency / race on guide double-booking
- [ ] All **11 new endpoints** from §1
- [ ] Alembic upgrade test

**Missing app-side tests (`frontend_flutter/test/`):**
- `routes_test.dart` (91 lines) and `domain_test.dart` (425 lines) both run
  against the **local** dataset (`LOCALIQ_OFFLINE` defaults true).
- **Zero tests touch `JsonApiClient`, `RemoteAuthService`, `RemotePlaceRepository`, or `RemoteContextRepository`.**
- No `mock`/`fake` package in `pubspec.yaml`.
- **Work:** add contract tests that hit the real backend. This is what would have caught the entire §0 mismatch.

---

## 9. DOCUMENTATION GAPS

- [ ] `frontend_flutter/docs/BACKEND_CONTRACT.md` is **stale**: it lists `GET /auth/me` and `POST /auth/logout` as consumed (lines 32, 37) — the app never calls either. It omits the Google Routes third-party call entirely, and omits that the session token is never attached.
- [ ] Root `README.md` — verify claims (48 experiences / 12 guides) against the actual dataset.
- [ ] No API examples / curl snippets for the new endpoints.
- [ ] No architecture diagram.

---

## 10. PRIORITISED BUILD ORDER

### Sprint 1 — Make one vertical slice real (2 days) 🔴
The goal: **the app talking to the backend, visibly.**
1. Fix §3.1 token injection + §3.2 `restore()` + §3.3 logout — *app-side but backend-blocking*
2. §1.1 `GET /places` + §1.2 `GET /places/{id}` + §1.3 `GET /places/{id}/experiences`
3. §2.1 `Place` table + seed
4. §5.1 real image URLs — *without this the demo looks broken*
5. §1.4 popular, §1.5 gems — *cheap, high demo value*
6. §2.7 Alembic

### Sprint 2 — The AI layer (1.5 days) 🟠
7. §1.6 `/places/discover` (adopt dead `services/parser.py`, §6.1)
8. §1.8 `/context/live` + §1.7 traffic + §6.7 weather cache
9. `/experiences/{id}` + `/weather` **shape fixes** (§11)

### Sprint 3 — Auth completeness (1 day) 🟠
10. §1.9 refresh, §1.10 guest, §1.11 forgot-password, §3.5 secret guard, §3.4 rate limit
11. §2.4 saved + app wiring

### Sprint 4 — Real bookings + content (1.5 days) 🟠
12. §4.1 **wire guides screen to the existing backend** — biggest perceived win per hour
13. §4.9 real booking state machine + fix `guides.py:24-44`
14. §2.2 `touristScore` + remaining Experience fields

### Sprint 5 — Polish (1 day) ⚪
15. §4.4 quests, §4.5 wallet (pure CRUD, models already exist)
16. §6 dead code, §9 docs, §8 tests
17. §4.12 admin, §4.10 notifications (if time)

### Explicitly skip
❌ §1.12 Google sign-in — delete the button, it throws today
❌ §6.2 `services/guide.py` — delete, it 500s if wired
❌ §4.3 social matching, §4.6 safety — large, low demo ROI
❌ JWT migration — opaque sessions are fine for a demo, just fix the token injection

---

## 11. THE TWO SHAPE MISMATCHES (quick reference)

These two routes **exist** but return the wrong JSON. Both fail silently —
the app parses them into empty/default objects rather than erroring.

### 11.1 `GET /experiences/{id}`
**App expects** (`remote_place_repository.dart:59`, → `Experience.fromJson` at `place.dart:227-250`):
`id` as String, `placeId`, `title`, `tagline`, `description`, `category`, `imageUrl`, `activityMinutes`, `typicalSpend`, `localScore` 0–100, `touristScore`, `highlights[]`, `bookingNote`, `weatherSuitability`, `practicalTip`

**Backend returns** (`app/schemas.py` ExperienceResponse): `id` int, `name`, `category` str, `avg_cost`, `duration_min`, `local_gem_score` 0–1, `indoor_outdoor` str, …

**Fix:** either rename the fields in `schemas.py`, or (better) build the app's shape in a dedicated response model so `JsonMapX` stops rescuing it.

### 11.2 `GET /weather`
**App expects** (`remote_context_repository.dart:17-21` → `WeatherSnapshot`, `context_models.dart:115-192`):
`temperature_c`, `condition` (enum), `apparent_temperature_c`, `humidity`, `precipitation_chance`, `wind_kph`, `uv_index`, `observed_at`, `sunrise`, `sunset`

**Backend returns** (`services/weather.py:50-94`): `temp_c`, `condition`, `is_rainy`, humidity, apparent temp

**Missing from the backend entirely:** `precipitation_chance`, `wind_kph`, `uv_index`, `sunrise`, `sunset`.
**Work:** either extend the Open-Meteo query string (it already supports all of these for free) or trim the app model. **Extending is nearly free — Open-Meteo returns them without a key.**

---

## 12. ONE-LINE SUMMARY FOR JUDGES

> The backend has a **real** recommendation engine, **real** auth, and **real**
> Ollama + Open-Meteo integrations. The Flutter app has a **real** product model
> (`Place → Experience`, 3-tier feasibility, taste profiles) and **real** screens.
> **The two have never been connected** — 11 endpoints are missing, the app's
> access token is never sent, and every backend image URL is empty.
> Sprint 1 closes that gap.
