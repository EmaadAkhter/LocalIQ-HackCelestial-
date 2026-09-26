# Jenkins (CI/CD)

Self-hosted Jenkins runs the build pipeline. Locally it listens on
`http://localhost:8081`; it is also published at
`https://jenkins.tavesglobal.com` so GitHub can deliver push webhooks.

> Exposing a Jenkins controller to the internet is a real risk. Here it is done
> deliberately and only for webhooks, gated by Jenkins' own login (anonymous
> read is disabled). See **Security** below.

## Run it

```bash
cd infra/jenkins
cp .env.example .env          # set a strong admin password + docker socket
docker compose -f docker-compose.jenkins.yml --env-file .env up -d --build
```

UI: `http://localhost:8081` locally, `https://jenkins.tavesglobal.com` publicly
(admin credentials from `.env`).

### Docker socket

The controller needs the Docker socket to build images. Set `DOCKER_SOCK` in
`infra/jenkins/.env`:

- Docker Desktop: `/var/run/docker.sock`
- Colima: `/Users/<you>/.colima/default/docker.sock`

## Configuration as Code

Jenkins is configured via JCasC (`infra/jenkins/casc/jenkins.yaml`):

- admin user (no signup),
- no anonymous read,
- system message and location (`https://jenkins.tavesglobal.com/`),
- a `localiq-ci` pipeline job pointing at `Jenkinsfile` on `main`,
- a `githubPush()` trigger so pushes to this repo start a build.

## GitHub push trigger (webhook)

The `localiq-ci` job has the **GitHub hook trigger for GITScm polling** enabled.
A repository webhook delivers pushes to Jenkins:

| Setting | Value |
|---|---|
| Payload URL | `https://jenkins.tavesglobal.com/github-webhook/` |
| Content type | `application/json` |
| Events | Just the `push` event |

Create it once (owner's machine, `gh` authenticated):

```bash
gh api --method POST repos/EmaadAkhter/LocalIQ-HackCelestial-/hooks \
  -f name=web \
  -f 'config[url]=https://jenkins.tavesglobal.com/github-webhook/' \
  -f 'config[content_type]=json' \
  -f 'config[insecure_ssl]=0' \
  -F active=true \
  -f 'events[]=push'
```

Verify a delivery (should be `status: OK`, HTTP `200`):

```bash
gh api repos/EmaadAkhter/LocalIQ-HackCelestial-/hooks/<hook-id>/deliveries \
  --jq '.[0] | {event, status, status_code}'
```

Jenkins must know its own public URL (`JENKINS_URL`) for the trigger to point
back correctly — it is set in `infra/jenkins/.env`.

## Pipeline (`Jenkinsfile`)

| Stage | What it does |
|---|---|
| Checkout | clone the repo |
| Backend: build images | `docker build backend/` (runtime) + `--target test` (dev deps) |
| Backend: tests | runs `pytest` in the test image, coverage gate at 80% |
| Backend: API smoke | starts the server in the image and checks health + parsing |
| Frontend: build image | builds `frontend_flutter/` if a Dockerfile exists |

> **Note (docker-outside-of-docker):** the Jenkins container talks to the host
> Docker daemon, so workspace paths are **not** visible to the daemon. Pipeline
> stages therefore run inside built images rather than bind-mounting the
> workspace. The full gateway-chain smoke test runs on the host via `make test`.

## Security

Jenkins is published at `https://jenkins.tavesglobal.com` on purpose, so GitHub
can reach `/github-webhook/`.

- Keep `JENKINS_ADMIN_PASSWORD` strong and out of git (`infra/jenkins/.env` is
  git-ignored).
- Anonymous read is disabled; the controller requires login.
- **Do not put Cloudflare Access in front of `/github-webhook/`** — Access
  intercepts the POST and GitHub deliveries fail. If you add Access for the UI,
  exclude the webhook path.
- Rotate the admin password if it is ever shared, and prefer SSH port-forwarding
  (`ssh -L 8081:localhost:8081`) for day-to-day admin work.
- Mounting the Docker socket gives Jenkins host-level control; treat it as trusted.

## Troubleshooting

- **JCasC errors:** check `docker compose logs jenkins`; the controller still
  starts if a job definition fails.
- **Cannot reach Docker:** verify `DOCKER_SOCK` and that the daemon is running.
- **Plugin download slow on first boot:** the image installs plugins at build
  time; the first build can take several minutes.
