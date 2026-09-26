# Contributing

Thanks for building LocalIQ. This document keeps the three of us in sync.

## Getting started

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) for environment setup, and
[`README.md`](README.md) for the architecture overview.

## Branching

- `main` is always deployable.
- Work on short-lived branches: `feat/<scope>`, `fix/<scope>`, `chore/<scope>`,
  `docs/<scope>`, `infra/<scope>`.
- Open a pull request into `main`. Keep PRs small and focused.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(ai): add constraint parser fallback
fix(gateway): correct Kong strip_path for /llm
docs(ethics): clarify data sourcing
chore(infra): bump Kong image
```

Scopes in use: `ai`, `backend`, `frontend`, `gateway`, `infra`, `ci`, `docs`.

## Code style

- Formatting is enforced by [`.editorconfig`](.editorconfig).
- **Python:** 4-space indent, type hints, docstrings on public functions.
- **Dart/Flutter:** 2-space indent, `flutter analyze` must pass.
- **YAML/shell:** 2-space indent; all shell scripts start with
  `#!/usr/bin/env bash` and `set -euo pipefail`.

## Checks before you push

Run the same checks CI runs:

```bash
make lint        # backend + frontend
make typecheck   # backend + frontend
make test        # smoke tests
```

## Pull requests

- Describe the change and how you verified it.
- Link the related issue if there is one.
- CI (Jenkins) must pass before merge.
- At least one teammate review for shared code.

## Reporting issues

Use the issue tracker with a clear title, reproduction steps, and expected vs
actual behaviour. Security issues follow [`SECURITY.md`](SECURITY.md).
