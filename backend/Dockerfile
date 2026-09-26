# syntax=docker/dockerfile:1
#
# Multi-stage build on Python 3.12 (LTS).
#   builder → resolves runtime dependencies into /opt/venv
#   test    → builder + dev dependencies (used by CI)
#   runtime → lean, non-root image with just the venv + app (default target)

# ---- builder -------------------------------------------------------------
FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# psycopg2-binary ships manylinux wheels, so no compiler is needed here.
COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

# ---- test ----------------------------------------------------------------
# Additive stage for CI: same base as builder plus the test tooling.
FROM builder AS test

COPY requirements-dev.txt ./
RUN pip install -r requirements-dev.txt

COPY . .
CMD ["python", "-m", "pytest", "-q"]

# ---- runtime -------------------------------------------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv

# Drop the installer and bytecode caches: nothing needs them at runtime.
RUN rm -rf /opt/venv/lib/python3.12/site-packages/pip* \
           /opt/venv/lib/python3.12/site-packages/wheel* \
           /opt/venv/bin/pip* \
    && find /opt/venv -name '__pycache__' -type d -prune -exec rm -rf {} +

COPY . .

RUN useradd --create-home --uid 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Healthcheck without pulling in curl.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health', timeout=3).status == 200 else 1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
