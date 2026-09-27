#!/usr/bin/env python3
"""Drive Nugen end to end: upload corpus -> align -> deploy.

Nugen's flow is asynchronous and stateful, so this script keeps a small state
file (`data/nugen/state.json`) between steps and can be re-run safely.

    python scripts/nugen_bootstrap.py all          # upload + align + deploy
    python scripts/nugen_bootstrap.py upload
    python scripts/nugen_bootstrap.py align
    python scripts/nugen_bootstrap.py deploy
    python scripts/nugen_bootstrap.py status       # poll everything once

The API key is read from NUGEN_API_KEY, or from backend/.env.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
STATE_PATH = ROOT / "data" / "nugen" / "state.json"
CORPUS = [
    ROOT / "data" / "nugen" / "constraint_extraction.txt",
    ROOT / "data" / "nugen" / "explanation_generation.txt",
]

BASE_URL = os.environ.get("NUGEN_BASE_URL", "https://api.nugen.in")
BASE_MODEL = os.environ.get("NUGEN_BASE_MODEL_ID", "llama-v3p2-3b-reasoning")
ALIGNMENT_NAME = "LocalIQ Constraint + Explanation Alignment"

TIMEOUT = httpx.Timeout(120.0, connect=20.0)


def _load_env_file() -> None:
    """Minimal .env reader so the script works outside docker-compose."""
    env_path = ROOT / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def api_key() -> str:
    _load_env_file()
    key = os.environ.get("NUGEN_API_KEY", "")
    if not key:
        sys.exit("NUGEN_API_KEY is not set (add it to backend/.env).")
    return key


def _headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {api_key()}"}


def _load_state() -> dict:
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text())
    return {}


def _save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2))


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------


def upload() -> list[str]:
    with httpx.Client(timeout=TIMEOUT, headers=_headers()) as client:
        files = [
            ("files", (p.name, p.read_bytes(), "text/plain")) for p in CORPUS
        ]
        data = {
            "categories": ["localiq", "localiq"],
            "names": [p.name for p in CORPUS],
        }
        resp = client.post(f"{BASE_URL}/api/v3/documents/create", files=files, data=data)
        resp.raise_for_status()
        doc_ids = resp.json().get("document_ids", [])
    print(f"uploaded {len(doc_ids)} document(s): {doc_ids}")

    # Wait for async processing.
    deadline = time.time() + 300
    while time.time() < deadline:
        with httpx.Client(timeout=TIMEOUT, headers=_headers()) as client:
            statuses = []
            for doc_id in doc_ids:
                r = client.get(f"{BASE_URL}/api/v3/documents/{doc_id}/status")
                r.raise_for_status()
                statuses.append(r.json().get("status"))
        print(f"  document statuses: {statuses}")
        if all(s in ("READY", "COMPLETED") for s in statuses):
            break
        time.sleep(10)
    return doc_ids


def align(document_ids: list[str]) -> str:
    payload = {
        "alignment_name": ALIGNMENT_NAME,
        "base_model_id": BASE_MODEL,
        "document_ids": document_ids,
        "description": (
            "LocalIQ: extract travel constraints (English/Hinglish) into strict "
            "JSON, and write concise feasibility-aware explanations."
        ),
    }
    with httpx.Client(timeout=TIMEOUT, headers=_headers()) as client:
        resp = client.post(
            f"{BASE_URL}/api/v3/alignment-projects/create", json=payload
        )
        resp.raise_for_status()
        alignment_id = resp.json()["alignment_id"]
    print(f"alignment created: {alignment_id}")
    return alignment_id


def poll_alignment(alignment_id: str) -> dict:
    with httpx.Client(timeout=TIMEOUT, headers=_headers()) as client:
        status = client.get(
            f"{BASE_URL}/api/v3/alignment-projects/{alignment_id}/status"
        ).json()
        detail = client.get(f"{BASE_URL}/api/v3/alignment-projects/{alignment_id}").json()
    return {"status": status, "detail": detail}


def wait_alignment(alignment_id: str, timeout_s: int = 3600) -> dict:
    deadline = time.time() + timeout_s
    last = None
    while time.time() < deadline:
        data = poll_alignment(alignment_id)
        status = (data["status"].get("status") or "").upper()
        if status != last:
            print(f"  alignment status: {status}")
            last = status
        if status in ("READY", "COMPLETED", "EVALUATED"):
            return data["detail"]
        if status in ("FAILED", "STOPPED"):
            print(json.dumps(data, indent=2)[:2000])
            sys.exit(f"alignment {status}")
        time.sleep(15)
    sys.exit("timed out waiting for alignment")


def deploy(model_id: str) -> None:
    with httpx.Client(timeout=TIMEOUT, headers=_headers()) as client:
        resp = client.post(f"{BASE_URL}/api/v3/models/{model_id}/deployment")
        if resp.status_code == 400 and "already deployed" in resp.text.lower():
            print("model already deployed")
            return
        resp.raise_for_status()
    print(f"deployment started for {model_id}")


def wait_deployment(model_id: str, timeout_s: int = 1800) -> None:
    deadline = time.time() + timeout_s
    last = None
    while time.time() < deadline:
        with httpx.Client(timeout=TIMEOUT, headers=_headers()) as client:
            data = client.get(
                f"{BASE_URL}/api/v3/models/{model_id}/deployment/status"
            ).json()
        status = (data.get("status") or "").upper()
        if status != last:
            print(f"  deployment status: {status}")
            last = status
        if status in ("READY", "DEPLOYED", "EVALUATED"):
            return
        if status == "FAILED":
            print(json.dumps(data, indent=2)[:2000])
            sys.exit("deployment failed")
        time.sleep(15)
    print("deployment still running; re-run `status` later")


def _extract_model_id(detail: dict) -> str | None:
    for key in ("model_id", "aligned_model_id", "deployed_model_id"):
        if detail.get(key):
            return detail[key]
    model = detail.get("model") or {}
    return model.get("model_id") if isinstance(model, dict) else None


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "step", choices=["all", "upload", "align", "deploy", "status"]
    )
    args = parser.parse_args()
    state = _load_state()

    if args.step in ("all", "upload"):
        state["document_ids"] = upload()
        _save_state(state)
    if args.step in ("all", "align"):
        if not state.get("document_ids"):
            sys.exit("no document_ids in state; run `upload` first")
        state["alignment_id"] = align(state["document_ids"])
        _save_state(state)
        detail = wait_alignment(state["alignment_id"])
        model_id = _extract_model_id(detail)
        if not model_id:
            print("alignment finished but no model_id yet; detail follows:")
            print(json.dumps(detail, indent=2)[:2000])
        else:
            state["model_id"] = model_id
            _save_state(state)
            print(f"aligned model_id: {model_id}")
    if args.step in ("all", "deploy"):
        model_id = state.get("model_id")
        if not model_id:
            sys.exit("no model_id in state; run `align` first")
        deploy(model_id)
        wait_deployment(model_id)
        print(f"\nReady. Put this in .env:\n  NUGEN_MODEL_ID={model_id}\n  NUGEN_ENABLED=true")
    if args.step == "status":
        print(json.dumps(state, indent=2))
        if state.get("alignment_id"):
            print(json.dumps(poll_alignment(state["alignment_id"]), indent=2)[:2000])


if __name__ == "__main__":
    main()
