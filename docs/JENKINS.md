# Jenkins (CI/CD)

Self-hosted Jenkins runs the build pipeline. It is **not** exposed publicly by
default — exposing a Jenkins controller to the internet is a serious risk.

## Run it

```bash
cd infra/jenkins
cp .env.example .env          # set a strong admin password + docker socket
docker compose -f docker-compose.jenkins.yml --env-file .env up -d --build
```

UI: `http://localhost:8081` (admin credentials from `.env`).

### Docker socket

The controller needs the Docker socket to build images. Set `DOCKER_SOCK` in
`infra/jenkins/.env`:

- Docker Desktop: `/var/run/docker.sock`
- Colima: `/Users/<you>/.colima/default/docker.sock`

## Configuration as Code

Jenkins is configured via JCasC (`infra/jenkins/casc/jenkins.yaml`):

- admin user (no signup),
- no anonymous read,
- system message and location,
- a `localiq-ci` pipeline job pointing at `Jenkinsfile` on `main`.

## Pipeline (`Jenkinsfile`)

| Stage | What it does |
|---|---|
| Checkout | clone the repo |
| Backend: build image | `docker build backend/` — validates the Python app |
| Backend: tests | `pytest` if `backend/tests/` exists |
| Stack: smoke test | `tests/smoke/smoke.sh` — full edge → Kong → backend chain |
| Flutter: analyze | runs only if `frontend_flutter/pubspec.yaml` exists |

## Security

- Keep the admin password strong and out of git.
- Do not add Jenkins to the public Cloudflare tunnel unless you accept the risk.
  If you must, gate it behind Cloudflare Access and rotate credentials.
- Mounting the Docker socket gives Jenkins host-level control; treat it as trusted.

## Troubleshooting

- **JCasC errors:** check `docker compose logs jenkins`; the controller still
  starts if a job definition fails.
- **Cannot reach Docker:** verify `DOCKER_SOCK` and that the daemon is running.
- **Plugin download slow on first boot:** the image installs plugins at build
  time; the first build can take several minutes.
