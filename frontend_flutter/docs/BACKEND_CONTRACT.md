# Backend integration contract

This document records how the Flutter app talks to the FastAPI backend in
`../backend`, and what (if anything) is still missing.

> **Status: connected.** The endpoint matrix below is green — the app can run
> backend-first with `LOCALIQ_OFFLINE=false` (now the default) and every remote
> repository has a matching, shape-compatible route. The remaining gaps are
> called out at the end.

## How the switch works

`lib/core/config/providers.dart` exposes `remoteDataEnabledProvider`; the
repository graph in `lib/core/providers.dart` reads it once and picks the local
or remote implementation per seam. **Backend-first is now the default:**

```bash
# default: backend-first
flutter run

# force the bundled offline dataset
flutter run --dart-define=LOCALIQ_OFFLINE=true

# point at another backend
flutter run --dart-define=LOCALIQ_API_BASE_URL=http://10.0.2.2:8000/api/v1
```

### Auth tokens

`JsonApiClient` attaches the signed-in user's access token to every request. The
token travels through `AuthTokenHolder` (`lib/core/network/auth_token_holder.dart`):
`RemoteAuthService` writes it on each session change, the client reads it per
request. There is no provider cycle — the client is built before the auth service
exists. A session token takes precedence over the static `LOCALIQ_API_KEY`.

`LocalIqApp` calls `AuthService.restore()` on cold start, and `signOut()` now
revokes the server session via `POST /auth/logout` before clearing local state.

## Endpoint matrix

Legend: **OK** = the backend serves a compatible route.

| Frontend seam | Endpoint | Backend | Notes |
| --- | --- | --- | --- |
| `RemoteAuthService.login` | `POST /auth/login` | OK | Returns `access_token` + `refresh_token` + `user`. |
| `RemoteAuthService.signUp` | `POST /auth/register` | OK | Accepts `terms_accepted`. |
| `RemoteAuthService.restore` | `POST /auth/refresh` | OK | Rotating refresh tokens. |
| `RemoteAuthService.signInWithGoogle` | `POST /auth/google` | OK | Needs an `idToken`; app-side `google_sign_in` still to add. |
| `RemoteAuthService.continueAsGuest` | `POST /auth/guest` | OK | Real anonymous `User` row. |
| `RemoteAuthService.sendPasswordReset` | `POST /auth/forgot-password` | OK | Dev returns a reset token in the response. |
| `RemoteAuthService.signOut` | `POST /auth/logout` | OK | Revokes the session. |
| — | `POST /auth/verify-email` | OK | Redeems the emailed token; sets `user.email_verified`. |
| — | `POST /auth/resend-verification` | OK | Throttled by a short cooldown; 429 with `Retry-After`. |
| — | `DELETE /auth/me` | OK | Erases the account and every row referencing it. |
| `RemotePlaceRepository.search` | `GET /places` | OK | `text`, `lat`, `lng`, `radius_km`, `categories`, `open_at`, `max_spend`. |
| `RemotePlaceRepository.placeById` | `GET /places/{id}` | OK | 404 → `null`. |
| `RemotePlaceRepository.experiencesForPlace` | `GET /places/{id}/experiences` | OK | |
| `RemotePlaceRepository.experienceById` | `GET /experiences/{id}` | OK | Carries the app field names (see below). |
| `RemotePlaceRepository.popularNearby` | `GET /places/popular` | OK | |
| `RemotePlaceRepository.localGems` | `GET /places/gems` | OK | |
| `RemotePlaceRepository.discover` | `GET /places/discover` | OK | `{places, experiences, interpreted_query}`. |
| `RemoteContextRepository.weatherAt` | `GET /weather` | OK | Full snapshot incl. wind/uv/precip/sunrise/sunset. |
| `RemoteContextRepository.trafficAt` | `GET /traffic` | OK | Honest IST hour-of-day heuristic, not a live feed. |
| `RemoteContextRepository.liveContext` | `GET /context/live` | OK | `{weather, traffic}`. |
| — | `GET /driver/trips*` | OK | Driver trip map: pickup, stops, drop-off, route, live position. |
| — | `POST /onboarding/user/*` | OK | Guided taste conversation. |
| — | `GET|POST /guides/onboarding/*` | OK | Fast guide onboarding + licence upload. |
| — | `POST /guide-bookings/{id}/transition` | OK | Booking state machine (requested → accepted → confirmed → in_progress → completed). `X-User-Id` states the actor; the rule table lives in `services/journey_rules.py`. |
| — | `GET/POST/DELETE /me/favorites` | OK | Saved experiences. |
| — | `GET /notifications` | OK | Newest first; `limit` clamped to 200. |
| — | `GET /notifications/unread-count` | OK | `{unread: n}` for a badge. |
| — | `POST /notifications/{id}/read` | OK | Scoped to the caller; 404 if it is not theirs. |
| — | `POST /notifications/read-all` | OK | `{updated: n}`. |
| — | `GET /quests*`, `GET /me/wallet` | OK | Quests and the experience passport. |

## Field mapping: `ExperienceResponse` → `Experience`

Resolved server-side. `Place` is **synthesised over `Experience`** (1:1) in
`backend/app/services/places.py`, and `ExperienceResponse` carries the app field
names directly (`title`, `placeId`, `activityMinutes`, `typicalSpend`,
`localScore`, `touristScore`, `weatherSuitability`, `highlights`, `bookingNote`,
`practicalTip`, …). `local_gem_score` is rescaled ×100 into `localScore`.

| App field | Backend source |
| --- | --- |
| `Place.id` / `Experience.placeId` | `str(Experience.id)` |
| `centre` (`GeoPoint`) | `lat` + `lng` |
| `area` / `address` | nearest `KNOWN_AREAS` anchor (≤4 km), else `"Mumbai"` |
| `openingHours` | `open_time`/`close_time`, expanded to a 7-day week |
| `priceLevel` (0–4) | banded from `avg_cost` |
| `crowdLevel` | mapped from `crowd_density_level` |
| `touristScore` | `(1 − local_gem_score) × 100` |
| `weatherSuitability` | derived from `indoor_outdoor` + tags |

## Google Sign-In

The backend verifies the ID token against Google's `tokeninfo` endpoint and
checks the audience. `GOOGLE_OAUTH_CLIENT_ID` accepts a **comma-separated list**,
because a token's `aud` depends on which client minted it — an Android sign-in
that passes `serverClientId` yields the **web** client id, not the Android one.
List every id in use (web + Android + iOS).

The client *secret* is not needed server-side: ID-token verification requires no
secret. It is only relevant to a future authorization-code exchange.

App-side, add `google_sign_in`, initialise it with
`serverClientId: <web client id>`, and send the resulting `idToken` to
`POST /auth/google`. With `GOOGLE_OAUTH_CLIENT_ID` empty the backend falls back
to decoding the token *without verifying it* — development only; production
refuses unverified tokens.

## Remaining gaps

1. **Client-side feasibility tiers.** `FeasibilityEngine`
   (`lib/features/recommendations/data/`) still ranks locally for the Explore
   feed; the backend's `POST /recommend` remains a separate, flat-scored surface.
   Porting the three-tier model server-side is the next high-value backend item.
2. **`google_sign_in` on the app.** The backend route is ready and the audience
   is configured; the plugin still has to supply an `idToken`.
3. **Contract tests.** Repository-level tests against the backend would catch
   shape drift. Today the coverage is the domain mappers plus the backend suite —
   this is the gap that let the app/backend drift originally.
4. **Notifications UI is not wired.** The app already has
   `features/social/presentation/notifications_screen.dart` (reached from the
   home header's bell), but it renders local data. The backend now serves
   `GET /notifications`, `unread-count`, `{id}/read` and `read-all`, so the
   screen and the header badge just need pointing at them.
5. **Payments are simulated.** The booking lifecycle is real, but
   `payment_status` is a status field — no money moves.

> Backend product surfaces that used to be listed here as missing — saves,
> wallet, quests, social/meetup, admin, guide onboarding and the booking state
> machine — are all implemented and covered by the backend suite.

## Environment values

```bash
flutter run \
  --dart-define=LOCALIQ_ENV=dev \
  --dart-define=LOCALIQ_API_BASE_URL=http://10.0.2.2:8000/api/v1 \
  --dart-define=LOCALIQ_OFFLINE=false
```

No key is ever committed. See the root README for the Google Maps / Places keys.
