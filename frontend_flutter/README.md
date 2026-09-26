# LocalIQ — Flutter frontend

Feasibility-first local discovery. The app ranks experiences against the
traveller's *actual* constraints (time, budget, opening hours, weather,
accessibility, group type, travel time) and splits every option into one of
three tiers — **feasible**, **partially suitable**, **not feasible** — each with
the specific reasons behind the verdict.

## Architecture

```
lib/
  app/          router, shell, top-level screens
  core/         config, error, network, theme, shared providers
  features/
    <feature>/
      domain/        entities + repository/service contracts
      data/          local + remote implementations
      application/   Riverpod controllers
      presentation/  screens and widgets
  shared/       UI kit
```

Widgets never talk to the network. The dependency direction is
`presentation → application → domain`, with `data` satisfying the `domain`
interfaces. Swapping the bundled dataset for a live backend is a provider
decision in `lib/core/providers.dart`, not a code change spread across screens.

State management is Riverpod (`flutter_riverpod` 3.x). Routing is `go_router`
with a `StatefulShellRoute.indexedStack` for the four primary destinations.

## Data sources

Local and remote implementations exist side by side for every seam. The
`remoteDataEnabledProvider` switch picks between them:

```bash
# Bundled dataset (default)
flutter run

# Against a backend
flutter run \
  --dart-define=LOCALIQ_OFFLINE=false \
  --dart-define=LOCALIQ_API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Read **[docs/BACKEND_CONTRACT.md](docs/BACKEND_CONTRACT.md)** before pointing
this at a real server. It documents the endpoint-by-endpoint gap against the
FastAPI service in `../backend`; several routes the remote repositories expect
do not exist there yet.

No secret is committed. Google Maps, Google Places and the backend token are all
supplied with `--dart-define` and read in exactly one place,
`lib/core/config/environment.dart`. The Profile screen shows which data source
and which environment the running build is actually configured with.

## Responsiveness

| Width | Layout |
| --- | --- |
| ≥ 1200 | Full navigation, multi-column content, sidebar, max-width container |
| 900–1199 | Adaptive multi-column |
| 640–899 | Collapsing columns |
| < 640 | Single column, bottom navigation |

## Tests

```bash
flutter analyze   # must report no issues
flutter test
```

- `test/domain_test.dart` — feasibility tiers, scoring, travel estimates,
  explanations, weather and traffic determinism.
- `test/routes_test.dart` — every route at every breakpoint, asserting no
  build or layout errors. This is what catches overflow regressions.

## Build

```bash
flutter build web --release
flutter build apk --release
```
