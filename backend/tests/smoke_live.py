"""Live smoke test: boots the real app and hits every endpoint."""

import json
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("APP_ENV", "test")

from fastapi.testclient import TestClient  # noqa: E402

from app.database import init_db  # noqa: E402
from app.seed import seed_database  # noqa: E402
from main import app  # noqa: E402

init_db()
seed_database()
client = TestClient(app)

results = []


def check(name, resp, expect=200, show=None):
    ok = resp.status_code == expect
    body = ""
    try:
        body = json.dumps(resp.json())[:220]
    except Exception:
        body = resp.text[:220]
    results.append((ok, name, resp.status_code, body))
    print(f"[{'OK ' if ok else 'FAIL'}] {name} -> {resp.status_code}")
    if show and ok:
        print(f"        {body}")
    return resp.json() if ok else None


print("=" * 70)
print("1. HEALTH + CONFIG")
print("=" * 70)
check("GET /health", client.get("/health"), show=True)
cfg = check("GET /api/v1/config", client.get("/api/v1/config"), show=True)
assert "google_places" not in json.dumps(cfg).lower(), "server key leaked in /config!"
print("        -> no server-side Google key in /api/v1/config  [OK]")

print()
print("=" * 70)
print("2. EXPERIENCES")
print("=" * 70)
exp = check("GET /api/v1/experiences?limit=3", client.get("/api/v1/experiences?limit=3"), show=True)
check("GET /api/v1/experiences?category=food", client.get("/api/v1/experiences?category=food&limit=3"))
check("GET /api/v1/experiences?q=fort", client.get("/api/v1/experiences?q=fort"))
check("GET /api/v1/experiences?min_rating=4.5", client.get("/api/v1/experiences?min_rating=4.5&limit=3"))
detail = check(
    "GET /api/v1/experiences/1/detail (route+weather)",
    client.get("/api/v1/experiences/1/detail?lat=19.0596&lng=72.8295"),
    show=True,
)
if detail:
    print(f"        route.source={detail['route']['source']} "
          f"distance_km={detail['distance_km']} travel={detail['travel_time_min']}min "
          f"polyline={'yes' if detail['route']['polyline'] else 'no'} "
          f"weather.available={detail['weather']['available']}")
check("GET /api/v1/experiences/99999 (404)", client.get("/api/v1/experiences/99999"), expect=404)
check("GET /api/v1/experiences/1/guides", client.get("/api/v1/experiences/1/guides"), show=True)

print()
print("=" * 70)
print("3. RECOMMEND (the main endpoint)")
print("=" * 70)
rec = check(
    "POST /api/v1/recommend (WALK, origin given)",
    client.post("/api/v1/recommend", json={
        "location": "Bandra", "time_hours": 4, "budget_inr": 1500,
        "group_type": "friends", "interests": ["food", "art"],
        "origin_lat": 19.0596, "origin_lng": 72.8295, "limit": 5,
    }),
    show=True,
)
if rec:
    r0 = rec["recommendations"][0]
    print(f"        candidates={rec['total_candidates']} feasible={rec['feasible_count']} "
          f"route_source={rec['route_source']} weather_used={rec['weather_used']}")
    print(f"        top={r0['name']!r} score={r0['score']:.3f} "
          f"dist={r0['distance_km']}km travel={r0['travel_time_min']}min "
          f"route={r0['route']['source']} polyline={'yes' if r0['route']['polyline'] else 'no'} "
          f"image={'yes' if r0['image'] else 'no'}")
    print(f"        why={r0['why_this_fits'][:90]!r}")
    print(f"        reasons={r0['reasons']}")
    assert rec["route_source"] == "google_routes", "Google route enrichment is NOT working"

check(
    "POST /api/v1/recommend (DRIVE)",
    client.post("/api/v1/recommend", json={
        "location": "Bandra", "time_hours": 3, "budget_inr": 2000,
        "travel_mode": "DRIVE", "origin_lat": 19.0596, "origin_lng": 72.8295, "limit": 3,
    }),
)
check(
    "POST /api/v1/recommend (no origin, no route)",
    client.post("/api/v1/recommend", json={"location": "Colaba", "limit": 3, "include_route": False}),
)
check(
    "POST /api/v1/recommend (rainy + accessibility)",
    client.post("/api/v1/recommend", json={
        "location": "Fort", "time_hours": 2, "budget_inr": 800,
        "accessibility": ["wheelchair"], "start_time": "18:00", "limit": 5,
    }),
)
check("POST /api/v1/recommend (invalid budget -> 422)", client.post(
    "/api/v1/recommend", json={"budget_inr": -5}), expect=422)

print()
print("=" * 70)
print("4. PLACES (Google Places API + SQLite fallback)")
print("=" * 70)
s = check("GET /api/v1/places/search?q=Bandra Fort", client.get(
    "/api/v1/places/search?q=Bandra%20Fort&lat=19.0596&lng=72.8295"), show=True)
if s:
    print(f"        source={s['source']} fallback={s['fallback']} count={s['count']}")
    for it in s["items"][:2]:
        print(f"        - {it['name']!r} {it['category']} {it['rating']}★ "
              f"cost={it['avg_cost']} hours={it['open_time']}-{it['close_time']} "
              f"img={it['image_url']}")
n = check("GET /api/v1/places/nearby", client.get(
    "/api/v1/places/nearby?lat=19.0596&lng=72.8295&limit=3"))
if n:
    print(f"        source={n['source']} first={n['items'][0]['name']!r} "
          f"dist={n['items'][0]['distance_km']}km")
img = s["items"][0]["image_url"] if s and s["items"] else None
if img:
    path = img if img.startswith("/") else "/" + img
    r = client.get(path)
    ok = r.status_code == 200 and r.headers.get("content-type", "").startswith("image/")
    results.append((ok, f"GET {path} (photo proxy)", r.status_code,
                    f"{len(r.content)} bytes {r.headers.get('content-type')}"))
    print(f"[{'OK ' if ok else 'FAIL'}] photo proxy -> {r.status_code} "
          f"{len(r.content)} bytes {r.headers.get('content-type')}")
check("GET /api/v1/integrations/status", client.get("/api/v1/integrations/status"), show=True)

print()
print("=" * 70)
print("5. WEATHER / PARSE / CHAT")
print("=" * 70)
check("GET /api/v1/weather", client.get("/api/v1/weather"), show=True)
check("GET /api/v1/weather?lat=&lon=", client.get("/api/v1/weather?lat=18.9388&lng=72.8354"))
p = check("POST /api/v1/parse", client.post("/api/v1/parse", json={
    "text": "I have 4 hours, Rs 1500 and want food and art around Bandra"}), show=True)
if p:
    print(f"        source={p['source']} constraints={p['constraints']}")
check("POST /api/v1/chat", client.post("/api/v1/chat", json={
    "experience_id": 1, "message": "Is this good for kids?"}), show=True)
check("POST /api/v1/chat (no experience)", client.post("/api/v1/chat", json={
    "message": "What should I do in Mumbai in 3 hours?"}))

print()
print("=" * 70)
print("6. GUIDES")
print("=" * 70)
gl = check("GET /api/v1/guides", client.get("/api/v1/guides"))
guide_id = gl[0]["id"] if gl else None
check(f"POST /api/v1/guides/{guide_id}/request", client.post(
    f"/api/v1/guides/{guide_id}/request",
    json={"name": "Smoke Test", "date": "2026-10-01", "hours": 3, "group_size": 4}), show=True)
check("POST /api/v1/guides/99999/request (404)", client.post(
    "/api/v1/guides/99999/request", json={}), expect=404)

print()
print("=" * 70)
print("7. AUTH")
print("=" * 70)
email = f"smoke-{uuid.uuid4().hex[:8]}@localiq.test"
tok = check("POST /api/v1/auth/register", client.post("/api/v1/auth/register", json={
    "name": "Smoke Tester", "email": email, "password": "SmokeTest123"}), expect=201)
check("POST /api/v1/auth/register (dup -> 409)", client.post("/api/v1/auth/register", json={
    "name": "Smoke Tester", "email": email, "password": "SmokeTest123"}), expect=409)
check("POST /api/v1/auth/register (bad email -> 400)", client.post("/api/v1/auth/register", json={
    "name": "Smoke Tester", "email": "notanemail", "password": "SmokeTest123"}), expect=400)
check("POST /api/v1/auth/register (short pw -> 422)", client.post("/api/v1/auth/register", json={
    "name": "X", "email": "a@b.com", "password": "123"}), expect=422)
check("POST /api/v1/auth/login", client.post("/api/v1/auth/login", json={
    "email": email, "password": "SmokeTest123"}))
check("POST /api/v1/auth/login (wrong pw -> 401)", client.post("/api/v1/auth/login", json={
    "email": email, "password": "WrongPass123"}), expect=401)
headers = {"Authorization": f"Bearer {tok['access_token']}"} if tok else {}
check("GET /api/v1/auth/me", client.get("/api/v1/auth/me", headers=headers), show=True)
check("GET /api/v1/auth/me (no token -> 401)", client.get("/api/v1/auth/me"), expect=401)
check("GET /api/v1/auth/me (bad token -> 401)", client.get(
    "/api/v1/auth/me", headers={"Authorization": "Bearer nope"}), expect=401)
mr = check("GET /api/v1/guides/me/requests", client.get(
    "/api/v1/guides/me/requests", headers=headers))
if mr:
    print(f"        {len(mr)} request(s), first ref={mr[0]['booking_ref']}")
check("GET /api/v1/auth/status", client.get("/api/v1/auth/status"), show=True)
check("POST /api/v1/auth/logout", client.post("/api/v1/auth/logout", headers=headers))
check("GET /api/v1/auth/me (after logout -> 401)", client.get(
    "/api/v1/auth/me", headers=headers), expect=401)

print()
print("=" * 70)
print("8. KEY LEAK SCAN (all responses must not contain server keys)")
print("=" * 70)
from app.config import get_settings  # noqa: E402

s_ = get_settings()
server_keys = {k for k in (s_.google_places_api_key, s_.google_routes_api_key) if k}
web_key = s_.google_maps_api_key_web
# A server key that is deliberately the same credential as the browser key is
# not a code leak (it is public by design), but it is a security caveat worth
# printing. Any *distinct* server key appearing in a response is a real leak.
distinct_server_keys = {k for k in server_keys if k != web_key}
shared = bool(server_keys & {web_key}) if web_key else False
leaks = []
probes = [
    ("/api/v1/config", client.get("/api/v1/config")),
    ("/api/v1/experiences?limit=2", client.get("/api/v1/experiences?limit=2")),
    ("/api/v1/experiences/1/detail?lat=19.05&lng=72.83", client.get("/api/v1/experiences/1/detail?lat=19.05&lng=72.83")),
    ("/api/v1/recommend", client.post("/api/v1/recommend", json={"limit": 2, "origin_lat": 19.05, "origin_lng": 72.83})),
    ("/api/v1/places/search?q=cafe", client.get("/api/v1/places/search?q=cafe")),
    ("/api/v1/guides", client.get("/api/v1/guides")),
    ("/api/v1/integrations/status", client.get("/api/v1/integrations/status")),
    ("/api/v1/auth/status", client.get("/api/v1/auth/status")),
]
for name, resp in probes:
    text = resp.text
    for k in distinct_server_keys:
        if k in text:
            leaks.append((name, "distinct-server-key"))
    if web_key and web_key in text and "/api/v1/config" not in name:
        leaks.append((name, "web-key"))
results.append((not leaks, "key-leak scan", 0, str(leaks) or "clean"))
print(f"[{'OK ' if not leaks else 'FAIL'}] key-leak scan: {leaks or 'clean'}")
if shared:
    print("  [WARN] GOOGLE_PLACES/ROUTES keys are the same credential as the "
          "browser key, so referrer restriction no longer shields it. "
          "Create a separate server key for production.")

print()
print("=" * 70)
failed = [r for r in results if not r[0]]
print(f"TOTAL: {len(results)} checks, {len(results) - len(failed)} passed, {len(failed)} failed")
if failed:
    print("\nFAILURES:")
    for _, name, code, body in failed:
        print(f"  - {name} ({code}) {body}")
print("=" * 70)
sys.exit(1 if failed else 0)
