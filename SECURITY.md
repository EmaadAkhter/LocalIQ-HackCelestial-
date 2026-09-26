# Security Policy

## Reporting a vulnerability

Please do not open a public issue for security problems. Report privately to the
team leads with:

- a description of the issue and its impact,
- steps to reproduce,
- any suggested fix.

We aim to acknowledge reports within 48 hours.

## Security considerations for this project

LocalIQ self-hosts a local LLM, a Jenkins controller, and a public tunnel. That
creates real attack surface. Keep the following in mind:

### Never expose an unauthenticated LLM

Ollama has no authentication of its own. Do not expose port `11434` directly to
the internet. Always route shared model access through Kong `key-auth` (the
`/llm/*` route) and rotate the shared key.

### Protect secrets

- Keep `.env` files out of git (they are gitignored).
- API keys, tunnel tokens, and Jenkins credentials must live in environment
  variables or a secret manager — never in source.
- The K8s manifests ship placeholder secrets. Replace them before deploying.

### Jenkins is high risk

- The controller is published at `https://jenkins.tavesglobal.com` so GitHub can
  deliver push webhooks. It requires login and anonymous read is disabled; keep
  the admin password strong and rotate it if it is ever shared.
- Do not place Cloudflare Access in front of `/github-webhook/` — it intercepts
  the POST and GitHub deliveries fail.
- Prefer SSH port-forwarding (`ssh -L 8081:localhost:8081`) for day-to-day admin
  work instead of using the public UI.
- Mounting the Docker socket into Jenkins grants it host-level control. Treat the
  controller as a trusted machine only.
- Keep plugins updated; Jenkins plugins are a common entry point.

### Tunnel hygiene

- LocalIQ uses a *named* Cloudflare tunnel (`localiq`) with DNS routes on
  `tavesglobal.com`. Exposed: the app/API, the key-auth shared LLM, and Jenkins.
- `/llm/*` is protected by Kong key-auth (`apikey`). Rotate
  `localiq-shared-key` before sharing the model widely.
- The tunnel credentials JSON (`infra/cloudflared/*.json`) is git-ignored. Treat
  it as a secret.

### API hardening

- **Rate limits** are enforced per client IP: reads 60/min, recommendations
  30/min, parse & chat 20/min, auth 10/min. Breaches return `429` in the standard
  error shape.
- **Login lockout:** 5 failed attempts lock an email for 15 minutes. Successful
  login clears the counter.
- **Passwords** require at least 8 characters with upper, lower and digit; only a
  salted PBKDF2 hash is stored.
- **Session tokens** are random and stored only as an HMAC-SHA256 hash.
- **CORS** is an explicit allow-list (`CORS_ORIGINS`); never set it to `*`.
- **Errors** never leak stack traces: unhandled exceptions return a generic
  `500` with a `request_id` for correlation (`X-Request-ID`).
- Rate-limit and lockout state is in-memory and per-process — move to Redis for a
  multi-replica deployment.

### Data and privacy

- The dataset is curated; do not scrape or store personal data.
- Any future user accounts must follow least-privilege and data-minimisation
  principles.

See [`docs/ETHICS.md`](docs/ETHICS.md) for the project's AI and data ethics stance.
