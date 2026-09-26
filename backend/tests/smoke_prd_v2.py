"""Live smoke test for the PRD v2 journeys against a real uvicorn server.

Boots the app on a throwaway SQLite database, then walks one traveller and one
guide through the full journey set over real HTTP.
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import httpx

BACKEND = Path(__file__).resolve().parent.parent
DB = BACKEND / "data" / "smoke_prd_v2.db"
PORT = 8123 + (os.getpid() % 500)
BASE = f"http://127.0.0.1:{PORT}"

passed = 0
failed: list[str] = []


def check(label: str, condition: bool, extra: str = "") -> None:
    global passed
    # The API returns rupee signs and other non-ASCII text; keep the console safe.
    extra = (extra or "").encode("ascii", "replace").decode("ascii")
    if condition:
        passed += 1
        print(f"  OK   {label}")
    else:
        failed.append(label)
        print(f"  FAIL {label} {extra}")


def main() -> int:
    for suffix in ("", "-wal", "-shm"):
        target = Path(str(DB) + suffix)
        if target.exists():
            target.unlink()

    env = {
        **dict(os.environ),
        "DATABASE_URL": f"sqlite:///{DB.as_posix()}",
    }
    proc = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "main:app",
            "--port",
            str(PORT),
            "--log-level",
            "warning",
        ],
        cwd=str(BACKEND),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        client = httpx.Client(base_url=BASE, timeout=30.0)
        # A cold start runs every migration and seeds 48 experiences, so allow
        # generous time before declaring the server dead.
        for _ in range(240):
            if proc.poll() is not None:
                output = ""
                if proc.stdout is not None:
                    try:
                        output = proc.stdout.read() or ""
                    except Exception:
                        output = "<unreadable>"
                print(f"server exited during startup (rc={proc.returncode}):\n{output[-3000:]}")
                return 1
            try:
                if client.get("/healthz").status_code == 200:
                    break
            except Exception:
                time.sleep(0.5)
        else:
            print("server never became healthy")
            return 1

        print("\n[1] solo journey")
        solo = client.post(
            "/api/v1/solo/explore",
            json={"location": "Bandra, Mumbai", "time_hours": 3, "budget_inr": 900},
        )
        check("solo explore 200", solo.status_code == 200, solo.text[:200])
        check("solo has results", bool(solo.json().get("results") is not None))
        companion = client.post(
            "/api/v1/solo/companion", json={"enabled": True, "personality": "foodie"}
        )
        check("companion echoes personality", companion.json().get("personality") == "foodie")

        print("\n[2] trust gate")
        users = []
        for name in ("Smoke Traveller", "Smoke Friend"):
            r = client.post(
                "/api/v1/auth/register",
                json={"name": name, "email": f"{name.lower().replace(' ', '_')}@smoke.test",
                      "password": "SmokePass123"},
            )
            check(f"register {name}", r.status_code in (200, 201), r.text[:200])
            # Registration returns a session token; resolve the id it belongs to.
            token = r.json().get("access_token") or r.json().get("token")
            me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
            check(f"auth/me for {name}", me.status_code == 200, me.text[:200])
            users.append(me.json()["id"])
        traveller, friend = users
        h_t, h_f = {"X-User-Id": str(traveller)}, {"X-User-Id": str(friend)}

        state = client.get("/api/v1/me/trust", headers=h_t).json()
        check("starts at basic", state["tier"] == "basic")
        blocked = client.post(
            "/api/v1/meetup/requests", json={"category": "food"}, headers=h_t
        )
        check("meetup blocked at basic tier", blocked.status_code == 403, blocked.text[:200])
        for tier in ("standard", "trusted"):
            step = client.post(
                "/api/v1/me/trust/verify", json={"target_tier": tier}, headers=h_t
            )
            check(f"verify -> {tier}", step.status_code == 200 and step.json()["tier"] == tier)
        skip = client.post(
            "/api/v1/me/trust/verify", json={"target_tier": "basic"}, headers=h_t
        )
        check("no downgrade", skip.status_code == 409)

        print("\n[3] meetup journey")
        req = client.post(
            "/api/v1/meetup/requests",
            json={"category": "food", "area": "Bandra, Mumbai", "interests": ["food", "walk"]},
            headers=h_t,
        )
        check("meetup request created", req.status_code == 201, req.text[:200])
        rid = req.json()["id"]
        friend_verify = client.post(
            "/api/v1/me/trust/verify", json={"target_tier": "standard"}, headers=h_f
        )
        check("friend verified", friend_verify.status_code == 200)
        cands = client.get(f"/api/v1/meetup/requests/{rid}/candidates", headers=h_t)
        check("candidates 200", cands.status_code == 200, cands.text[:200])
        match = client.post(f"/api/v1/meetup/requests/{rid}/match", json={}, headers=h_t)
        check("match formed", match.status_code in (200, 201), match.text[:200])
        if match.status_code in (200, 201):
            mid = match.json()["id"]
            get_match = client.get(f"/api/v1/meetup/matches/{mid}", headers=h_t)
            check("match readable by member", get_match.status_code == 200)
            confirm = client.post(
                f"/api/v1/meetup/matches/{mid}/status",
                json={"status": "confirmed"},
                headers=h_t,
            )
            check("match confirmed", confirm.status_code == 200, confirm.text[:200])

        print("\n[4] group journey")
        group = client.post(
            "/api/v1/groups",
            json={"name": "Smoke Group", "interests": ["food"], "budget_inr": 2000},
            headers=h_t,
        )
        check("group created", group.status_code == 201, group.text[:200])
        gid = group.json()["id"]
        joined = client.post(
            f"/api/v1/groups/{gid}/members",
            json={"interests": ["walk"], "budget_inr": 800, "time_hours": 2},
            headers=h_f,
        )
        check("member joined", joined.status_code in (200, 201), joined.text[:200])
        options = client.post(f"/api/v1/groups/{gid}/options", json={}, headers=h_t)
        check("options generated", options.status_code in (200, 201), options.text[:200])
        option_id = options.json()[0]["id"]
        for hdr in (h_t, h_f):
            vote = client.post(
                f"/api/v1/groups/{gid}/votes",
                json={"option_id": option_id, "rank": 1},
                headers=hdr,
            )
            check("vote cast", vote.status_code in (200, 201), vote.text[:200])
        tally = client.get(f"/api/v1/groups/{gid}/votes", headers=h_t)
        check("quorum reached", tally.json()["quorum_reached"] is True, tally.text[:200])
        check("group auto-locked", tally.json()["status"] == "locked", tally.text[:200])

        print("\n[5] guide journey")
        guide = client.post(
            "/api/v1/guides/onboard",
            json={"name": "Smoke Guide", "rate_per_hour": 900, "specialty": "street food"},
            headers=h_f,
        )
        check("guide onboarded", guide.status_code == 201, guide.text[:200])
        guide_id = guide.json()["guide_id"]
        blocked_pub = client.post(f"/api/v1/guides/{guide_id}/publish", json={}, headers=h_f)
        check("cannot publish before verification", blocked_pub.status_code == 409)
        ver = client.post(
            f"/api/v1/guides/{guide_id}/verification",
            json={"document_type": "aadhaar", "document_reference": "XXXX-4321"},
            headers=h_f,
        )
        check("verified", ver.status_code == 200 and ver.json()["verification_status"] == "verified")
        check("id reference masked", "XXXX-4321" not in ver.text)
        pub = client.post(f"/api/v1/guides/{guide_id}/publish", json={}, headers=h_f)
        check("published", pub.status_code == 200 and pub.json()["is_published"] is True)
        intruder = client.post(f"/api/v1/guides/{guide_id}/publish", json={}, headers=h_t)
        check("other user cannot publish", intruder.status_code == 403)
        slot = client.post(
            f"/api/v1/guides/{guide_id}/availability",
            json={"date": "2027-01-10", "start_time": "10:00", "end_time": "14:00",
                  "max_group_size": 6},
            headers=h_f,
        )
        check("slot created", slot.status_code == 201, slot.text[:200])
        quote = client.get(
            f"/api/v1/guides/{guide_id}/quote",
            params={"duration_min": 90, "group_size": 2, "extras_per_head": 50},
        )
        check("quote = 2h x 900 + 2 x 50", quote.json()["total_cost"] == 1900, quote.text[:200])
        booking = client.post(
            "/api/v1/guide-bookings",
            json={
                "guide_id": guide_id,
                "availability_id": slot.json()["id"],
                "date": "2027-01-10",
                "start_time": "10:00",
                "duration_min": 90,
                "group_size": 2,
                "extras_per_head": 50,
            },
            headers=h_t,
        )
        check("booking created", booking.status_code == 201, booking.text[:200])
        bid = booking.json()["id"]
        for status_name, hdr, expect in (
            ("accepted", h_f, 200),
            ("confirmed", h_t, 200),
            ("in_progress", h_f, 200),
            ("completed", h_f, 200),
        ):
            step = client.post(
                f"/api/v1/guide-bookings/{bid}/transition",
                json={"status": status_name},
                headers=hdr,
            )
            check(f"booking -> {status_name}", step.status_code == expect, step.text[:200])
        review = client.post(
            f"/api/v1/guide-bookings/{bid}/reviews",
            json={"rating": 5, "comment": "great", "punctuality": 5, "knowledge": 4},
            headers=h_t,
        )
        check("review left", review.status_code == 201, review.text[:200])
        growth = client.get(f"/api/v1/guides/{guide_id}/growth").json()
        check("rating recorded", growth["average_rating"] == 5.0, str(growth)[:200])
        course = client.post(
            f"/api/v1/guides/{guide_id}/trainings",
            json={"course_code": "SMOKE-SAFE", "grants_tier": "silver"},
            headers=h_f,
        )
        check("training enrolled", course.status_code == 201, course.text[:200])
        passed_course = client.post(
            f"/api/v1/guides/{guide_id}/trainings/{course.json()['id']}/complete",
            json={"score": 88},
            headers=h_f,
        )
        check("training passed", passed_course.status_code == 200, passed_course.text[:200])
        check("tier upgraded", client.get(f"/api/v1/guides/{guide_id}/growth").json()["tier"] == "silver")

        print("\n[6] hidden gems")
        gem = client.post(
            "/api/v1/gems",
            json={"name": "Smoke Gem", "lat": 19.11, "lng": 72.91, "area": "Bandra",
                  "category": "food"},
            headers=h_t,
        )
        check("gem submitted", gem.status_code == 201, gem.text[:200])
        cid = gem.json()["id"]
        early = client.post(f"/api/v1/gems/{cid}/promote", headers=h_t)
        check("cannot promote before approval", early.status_code == 409)
        for _ in range(3):
            client.post(f"/api/v1/gems/{cid}/vote", json={"approve": True})
        promoted = client.post(f"/api/v1/gems/{cid}/promote", headers=h_t)
        check("gem promoted", promoted.status_code == 201, promoted.text[:200])

        print("\n[7] quests")
        quests = client.get("/api/v1/quests")
        check("quests listed", quests.status_code == 200, quests.text[:200])
        if quests.json():
            qid = quests.json()[0]["id"]
            started = client.post(f"/api/v1/quests/{qid}/start", json={}, headers=h_t)
            check("quest started", started.status_code in (200, 201), started.text[:200])
            if started.status_code in (200, 201):
                run_id = started.json()["run_id"]
                for position in range(1, started.json()["stops_total"] + 1):
                    visit = client.post(
                        f"/api/v1/quests/runs/{run_id}/stops/{position}",
                        json={"stop_position": position},
                        headers=h_t,
                    )
                    check(f"stop {position} visited", visit.status_code == 200, visit.text[:200])
                done = client.post(f"/api/v1/quests/runs/{run_id}/complete", json={}, headers=h_t)
                check("quest completed", done.status_code == 200, done.text[:200])
                check("xp awarded", done.json()["xp_awarded"] > 0, done.text[:200])

        print("\n[8] legacy surface")
        for path in ("/api/v1/experiences", "/api/v1/guides"):
            r = client.get(path)
            check(f"{path} still 200", r.status_code == 200, r.text[:120])
        # The pre-existing auth-protected surface still works with its token.
        fav = client.get("/api/v1/me/favorites", headers={"Authorization": f"Bearer {token}"})
        check("/api/v1/me/favorites still 200", fav.status_code == 200, fav.text[:200])
        rec = client.post(
            "/api/v1/recommend",
            json={"location": "Bandra, Mumbai", "time_hours": 3, "budget_inr": 800},
        )
        check("/api/v1/recommend still works", rec.status_code == 200, rec.text[:200])
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()

    print(f"\n{'=' * 50}\npassed={passed} failed={len(failed)}")
    for name in failed:
        print("  FAILED:", name)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
