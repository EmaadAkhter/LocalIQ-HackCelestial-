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

- Do not expose the Jenkins UI publicly without strong authentication. Prefer an
  SSH tunnel or a private network.
- Mounting the Docker socket into Jenkins grants it host-level control. Treat the
  controller as a trusted machine only.
- Keep plugins updated; Jenkins plugins are a common entry point.

### Tunnel hygiene

- Cloudflare quick tunnels are public by default. Anyone with the URL can reach
  the app. Use named tunnels with access policies for anything sensitive.
- Treat the tunnel URL as a secret.

### Data and privacy

- The dataset is curated; do not scrape or store personal data.
- Any future user accounts must follow least-privilege and data-minimisation
  principles.

See [`docs/ETHICS.md`](docs/ETHICS.md) for the project's AI and data ethics stance.
