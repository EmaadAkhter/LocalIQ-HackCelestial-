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
| Backend: tests | runs `pytest` inside the built image |
| Backend: API smoke | starts the server in the image and checks health + parsing |
| Frontend: build image | builds `frontend_flutter/` if a Dockerfile exists |

> **Note (docker-outside-of-docker):** the Jenkins container talks to the host
> Docker daemon, so workspace paths are **not** visible to the daemon. Pipeline
> stages therefore run inside built images rather than bind-mounting the
> workspace. The full gateway-chain smoke test runs on the host via `make test`.

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
