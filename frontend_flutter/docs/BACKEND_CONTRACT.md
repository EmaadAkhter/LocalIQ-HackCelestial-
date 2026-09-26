# Backend integration contract

This document records the **exact** gap between the remote repositories in this
Flutter app and the FastAPI backend that already lives in `../backend`.

It exists so the next person does not have to rediscover the mismatch, and so
nobody assumes `LOCALIQ_OFFLINE=false` is enough to make the app talk to the
backend. **It is not enough.** See "Gaps" below.

## How the switch works

`lib/core/config/providers.dart` exposes `remoteDataEnabledProvider`. The
repository graph in `lib/core/providers.dart` reads it once and picks either
the local or the remote implementation for each seam. `local` is the default:

```bash
flutter run --dart-define=LOCALIQ_OFFLINE=false
```

The base URL comes from `Environment.apiBaseUrl` in
`lib/core/config/environment.dart`, overridable with `--dart-define=LOCALIQ_API_BASE_URL=...`.

## Endpoint matrix

Legend: **OK** = the backend serves a compatible route · **SHAPE** = the route
exists but the field names differ · **MISSING** = the backend has no such route.

| Frontend seam | Endpoint the frontend calls | Backend | Notes |
| --- | --- | --- | --- |
| `RemoteAuthService.login` | `POST /auth/login` | OK | Backend returns `access_token` / `expires_in` / `user`. |
| `RemoteAuthService.register` | `POST /auth/register` | SHAPE | Backend wants `name`; the frontend model also carries `name`. Verify. |
| `RemoteAuthService.currentUser` | `GET /auth/me` | OK | Requires bearer token. |
| `RemoteAuthService.refresh` | `POST /auth/refresh` | MISSING | Backend has no refresh endpoint. |
| `RemoteAuthService.signInWithGoogle` | `POST /auth/google` | MISSING | No social login on the backend. |
| `RemoteAuthService.continueAsGuest` | `POST /auth/guest` | MISSING | Guest mode is frontend-only. |
| `RemoteAuthService.requestPasswordReset` | `POST /auth/forgot-password` | MISSING | No reset flow on the backend. |
| `RemoteAuthService.signOut` | `POST /auth/logout` | OK | Backend revokes the session. |
| `RemotePlaceRepository.search` | `GET /places` | MISSING | Backend exposes `GET /experiences` only. |
| `RemotePlaceRepository.placeById` | `GET /places/{id}` | MISSING | |
| `RemotePlaceRepository.experiencesForPlace` | `GET /places/{id}/experiences` | MISSING | |
| `RemotePlaceRepository.experienceById` | `GET /experiences/{id}` | SHAPE | See "Field mapping" below. |
| `RemotePlaceRepository.popularNearby` | `GET /places/popular` | MISSING | |
| `RemotePlaceRepository.localGems` | `GET /places/gems` | MISSING | |
| `RemotePlaceRepository.discover` | `GET /places/discover` | MISSING | Closest backend analogue is `POST /parse`. |
| `RemoteContextRepository.weatherAt` | `GET /weather` | SHAPE | Backend returns `temp_c` / `condition` / `is_rainy`, not the frontend's snapshot shape. |
| `RemoteContextRepository.trafficAt` | `GET /traffic` | MISSING | No traffic service on the backend. |
| `RemoteContextRepository.liveContext` | `GET /context/live` | MISSING | Frontend-only convenience route. |

## Field mapping: `ExperienceResponse` → `Experience`

The backend models one entity where this app models two (`Place` and
`Experience`). See `lib/features/places/domain/place.dart` for the target shape.

| Backend field | Frontend field | Notes |
| --- | --- | --- |
| `id` (int) | `id` (String) | Needs a stringification at the boundary. |
| `name` | `place.name` | |
| `category` | `category` (enum) | Backend uses a plain string; the frontend uses `ExperienceCategory`. |
| `lat` / `lng` | `centre` (`GeoPoint`) | Flat pair vs nested object. |
| `avg_cost` | `typicalSpend` | |
| `duration_min` | `activityMinutes` | |
| `open_time` / `close_time` (strings) | `hours` (`OpeningHours`) | Needs a per-weekday expansion. |
| `rating` | `rating` (0–5) | |
| `image_url` | `imageUrl` | |
| `tags` | partly `crowdLevel` / `flexibleTiming` | No direct equivalent. |
| `accessibility_flags` | `accessibility` (enum flags) | |
| `indoor_outdoor` | `indoor` (bool) | String → bool. |
| `local_gem_score` (0–1) | `localScore` (0–100) | Needs a ×100 rescale. |
| — | `touristScore` | **No backend equivalent.** The local↔tourist axis is frontend-owned for now. |

## Gaps, ranked by effort

1. **`/places/*` is the big one.** The frontend's discovery model is
   `Place -> Experience`, and the backend is a flat `Experience` table. Either
   add a `places` router that groups experiences by venue, or collapse the
   frontend model. The former is much cheaper and preserves the product.
2. **Local↔tourist scoring.** The backend has `local_gem_score` but nothing for
   the visitor side of the axis that `FeasibilityEngine` ranks on. Either add
   `tourist_score` server-side, or keep the axis client-side deliberately.
3. **Feasibility tiers.** `FeasibilityEngine`
   (`lib/features/recommendations/data/`) is the product's differentiator and is
   currently frontend-only. The backend's `POST /recommend` returns a flat
   scored list with a single `feasible_count`, not three tiers with per-constraint
   reasons. Porting it server-side is the highest-value backend work.
4. **Assistant.** The frontend's `AssistantService` answers only from the active
   recommendation state. The backend's `POST /chat` is a per-experience guide
   bot. These are different products; they can coexist, but the frontend should
   not be pointed at `/chat` until the intent is settled.
5. **Traffic.** `LocalContextRepository` synthesises traffic from the clock.
   The backend has no equivalent.

## Environment values

```bash
flutter run \
  --dart-define=LOCALIQ_ENV=dev \
  --dart-define=LOCALIQ_API_BASE_URL=http://10.0.2.2:8000/api/v1 \
  --dart-define=LOCALIQ_OFFLINE=false
```

No key is ever committed. See `frontend_flutter/.env.example` style docs in the
root README for the Google Maps / Places keys.
