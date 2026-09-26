# LocalIQ — Build Plan (Self-Hosted, Local-First)

**Team Nexify | HackCelestial 3.0 | PS-6**
**Goal:** A working, demo-ready LocalIQ for Mumbai, fully self-hosted on your laptop, tunneled via Cloudflare, with a local LLM for parsing + guide chat, local SQLite DB, and a polished Next.js frontend.

---

## 1. Current State

- **Frontend:** Next.js 16 + Tailwind 4 scaffold. All custom folders (`components`, `hooks`, `store`, `types`, `lib/*`) are empty. `page.tsx` is the default Vercel starter.
- **Backend:** Empty FastAPI-style folder structure. `venv` has FastAPI/Pydantic/SQLModel/Uvicorn/Alembic/httpx/python-dotenv installed, but no `main.py`, `requirements.txt`, `.env`, or business logic. `data/` is empty.
- **Dataset:** None seeded.
- **README / docs:** None at repo root.
- **Deployment:** No scripts, no Cloudflare Tunnel config.

**Verdict:** Repo is a skeleton. Needs cleanup + full implementation.

---

## 2. Cleanup (Do First)

1. **Root README:** Add setup/run instructions, stack, demo notes, and fallback plan.
2. **Backend hygiene:**
   - Create `backend/main.py`, `backend/requirements.txt`, `backend/.env.example`.
   - Remove or ignore empty placeholder folders if not used; keep only folders that will have files.
   - Ensure `venv` is in `.gitignore`.
3. **Frontend hygiene:**
   - Delete default starter content from `page.tsx`/`layout.tsx` metadata.
   - Remove unused empty folders or keep them with an explicit `index.ts` barrel file once populated.
   - Ensure `node_modules` is ignored.
4. **Unify workspace:** Add a root `package.json` or `justfile`/`Makefile` with commands to start backend + frontend + tunnel together.

---

## 3. AI-Heavy Work (Local LLM)

**Model choice:** A small local model runnable on your laptop, e.g.:
- **Llama 3.1/3.2 (8B or smaller)** via **Ollama** (recommended — easiest on macOS).
- **Qwen2.5 7B / Mistral 7B / Phi-4** as fallback if 8B is too slow.
- For constraint parsing, prefer a model fine-tuned for JSON/structured output.

**Tasks:**
1. **Install & run Ollama locally.** Pull chosen model(s).
2. **Constraint parser:**
   - Prompt the local model to extract JSON: `{ location, time_hours, budget_inr, group_type, interests[], accessibility?, start_time? }`.
   - Use a strict prompt + Zod validation on the frontend / Pydantic on the backend.
   - Fallback: regex/heuristic parser + pre-canned demo responses.
3. **AI Guide chat:**
   - System prompt injects the selected experience’s context (name, category, hours, price, description, lat/lng).
   - Stream responses via Ollama’s `/api/generate` endpoint.
   - Keep conversation history in frontend state.
4. **Explainability generator:**
   - Use template-based explanations as default (fast, deterministic).
   - Optional local-LLM polish for “why this fits” text if performance allows.
5. **Performance guardrails:**
   - Cap context length.
   - Use `num_predict` / `temperature` tuning.
   - Pre-warm model before demo.

**Deliverables:**
- `backend/app/services/llm.py` — Ollama client wrapper.
- `backend/app/api/v1/parse.py` — natural-language constraint extraction endpoint.
- `backend/app/api/v1/chat.py` — context-aware guide chat endpoint.
- Frontend chat panel component.

---

## 4. Backend-Heavy Work (FastAPI + SQLite)

**Stack:** FastAPI, SQLModel (Pydantic v2), SQLite, Uvicorn, python-dotenv, httpx.

**Tasks:**
1. **Project bootstrap:**
   - `main.py` with FastAPI app, CORS, lifespan startup.
   - `requirements.txt` pinned.
   - `.env.example` for `DATABASE_URL`, `OLLAMA_URL`, `OLLAMA_MODEL`, `GOOGLE_MAPS_API_KEY` (optional, for map loads only).
2. **Database schema (SQLite):**
   - `Experience` table: id, name, category, lat, lng, avg_cost, duration_min, open_time, close_time, rating, description, image_url, tags, accessibility_flags, indoor_outdoor, local_gem_score.
   - `Guide` table: id, experience_id, name, photo, languages, specialty, rate_per_hour, rating (mocked profiles).
   - `Itinerary` / `ItineraryStop` tables (optional, for save/share feature).
3. **Seed data:**
   - Curate 40–60 real Mumbai experiences (food, culture, shopping, art, nightlife, outdoor).
   - Seed via SQLModel or a JSON → SQLite script.
   - Include 2–3 mocked guide profiles per major experience/area.
4. **Feasibility engine:**
   - Hard filters: time (travel + duration + buffer), budget, open hours, accessibility.
   - Travel-time estimate using haversine distance + speed heuristic (or Google Distance Matrix cached offline).
5. **Ranking engine:**
   - Weighted sum: interest match, time fit, budget fit, distance, rating, weather/context boost.
   - Endpoint: `POST /api/v1/recommend`.
6. **Weather adapter:**
   - Fetch live Open-Meteo weather for Mumbai.
   - Boost indoor/outdoor recommendations accordingly.
7. **Guide endpoints:**
   - `GET /api/v1/experiences/{id}/guides` — mocked guide profiles.
   - `POST /api/v1/guides/{id}/request` — mock request form endpoint.
8. **Health / fallback endpoints:**
   - `/health` for tunnel checks.
   - Cached dataset served if external APIs fail.

**Deliverables:**
- `backend/main.py`
- `backend/app/models.py`
- `backend/app/database.py`
- `backend/app/seed.py`
- `backend/app/services/recommender.py`
- `backend/app/services/weather.py`
- `backend/app/api/v1/experiences.py`, `recommendations.py`, `guides.py`, `parse.py`, `chat.py`, `weather.py`
- `backend/data/mumbai_experiences.json`

---

## 5. Frontend-Heavy Work (Next.js 16 + Tailwind 4)

**Tasks:**
1. **Layout & design system:**
   - Update `layout.tsx` metadata to LocalIQ.
   - Color palette + typography tokens in `globals.css`.
   - Mobile-responsive container.
2. **State management:**
   - Use React Context or Zustand (add if needed) for: user constraints, results, selected experience, chat history, mini-itinerary.
3. **Input screen:**
   - Form fields: location, time, budget, group type, interests (tags), accessibility toggles.
   - Natural language input box with voice input (Web Speech API).
   - Submit calls `/api/v1/parse` (optional) then `/api/v1/recommend`.
4. **Results screen:**
   - Card grid with image, name, distance, time, cost, rating, “why this fits” tag.
   - Show raw count vs feasible count (the “12 → 4” reveal).
   - Dynamic re-rank panel with budget + time sliders.
5. **Map view:**
   - Google Maps JS embed showing pins for top recommendations.
6. **Detail view:**
   - Experience details, images, open hours.
   - “Add to plan” button.
   - “Get a Guide” button → AI guide chat panel + human guide mock profiles.
7. **Mini-itinerary builder:**
   - Sidebar showing selected stops, total time/cost, connected route on map.
8. **Weather banner:**
   - Live Mumbai weather from backend with context-aware messaging.
9. **Polish:**
   - Loading skeletons, empty states, error toasts, smooth transitions with Framer Motion.

**Deliverables:**
- `frontend/src/app/page.tsx` (input + results split view or wizard).
- `frontend/src/components/forms/ConstraintForm.tsx`
- `frontend/src/components/results/RecommendationCard.tsx`, `RecommendationList.tsx`
- `frontend/src/components/experience/ExperienceDetail.tsx`, `GuidePanel.tsx`, `AIChat.tsx`
- `frontend/src/components/layout/Header.tsx`
- `frontend/src/hooks/useRecommendations.ts`, `useSpeech.ts`, `useWeather.ts`
- `frontend/src/lib/api/client.ts`
- `frontend/src/lib/feasibility/types.ts`
- `frontend/src/store/appStore.ts`

---

## 6. Integration & Deployment

1. **CORS:** Backend allows frontend origin (`localhost:3000` and tunnel domain).
2. **Single-command startup:**
   - `make dev` starts backend (`uvicorn main:app --reload`) and frontend (`npm run dev`).
   - `make tunnel` starts Cloudflare Tunnel in `screen`/`tmux`.
3. **Cloudflare Tunnel:**
   - Install `cloudflared`.
   - Create tunnel, get public URL, save config.
   - Document how to keep laptop awake / prevent sleep.
4. **Build for static or self-host:**
   - Next.js `output: 'export'` or run `next start` behind the same FastAPI server.
   - Recommended for hackathon: serve built frontend statically from FastAPI (`app.mount('/static', StaticFiles)`) so only one port/tunnel is needed.
5. **Fallback plan:**
   - Canned LLM responses for the exact demo sentence.
   - Cached dataset always returned if Ollama/weather fails.
   - Localhost demo ready if tunnel dies.

**Deliverables:**
- `Makefile` or `justfile`
- `cloudflared` tunnel config instructions in README
- Backend static-file serving setup

---

## 7. Suggested Build Order

| Phase | Focus | Owner | Hours |
|---|---|---|---|
| 0 | Cleanup repo, README, requirements, .env | Backend + Lead | 1 |
| 1 | Seed Mumbai dataset (40–60 experiences + guides) | Backend / Data | 3–4 |
| 2 | SQLite schema, FastAPI bootstrap, `/recommend` endpoint | Backend | 3–4 |
| 3 | Feasibility + ranking engine working end-to-end | Backend | 3–4 |
| 4 | Input form + results cards + explainability | Frontend | 4–5 |
| 5 | Dynamic re-ranking slider panel | Frontend | 2–3 |
| 6 | Map pins + detail view + “Add to plan” | Frontend | 3–4 |
| 7 | Local LLM setup (Ollama) + `/parse` + `/chat` | AI / Backend | 3–4 |
| 8 | AI guide panel + mocked human guide profiles | Frontend + Backend | 2–3 |
| 9 | Weather banner + voice input | Frontend | 2 |
| 10 | Cloudflare tunnel + one-command launch + rehearsal | DevOps / All | 2–3 |

**Total estimated effort:** ~28–36 focused hours.

---

## 8. MUST vs SHOULD vs COULD

**MUST (demo dies without these):**
- Seeded Mumbai dataset.
- Working feasibility + ranking engine.
- Input form + results cards + explainability.
- Dynamic re-ranking slider.
- Live demo via Cloudflare Tunnel.

**SHOULD (strong pitch):**
- Local LLM constraint parsing.
- AI guide chat.
- Weather adaptation banner.
- Map with pins.
- Mocked human guide profiles.

**COULD (if time permits):**
- Mini-itinerary builder.
- Voice input.
- Save/share plan.
- Provider-side static mockup.

**WON’T (this hackathon):**
- Real bookings/payments.
- Real human-guide marketplace.
- Multi-city scale / production auth.
- Trained ML recommender.

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Local LLM too slow | Pre-warm model; use smaller 3B–7B model; fallback to heuristic parser + canned chat responses. |
| Laptop sleeps / tunnel dies | Disable sleep, keep charger plugged, run tunnel in `tmux`, have localhost fallback. |
| Venue wifi blocks tunnel | Test on venue network ahead of time; have phone hotspot ready; recorded video fallback. |
| Google Maps API quota/failure | Use Google Maps JS Essentials SKU; cache static map images; fallback to list-only view. |
| Scope creep | Lock features at Phase 7; no new features after that. |

---

## 10. Definition of Done

- [ ] `make dev` starts backend + frontend cleanly.
- [ ] `make tunnel` exposes the app publicly.
- [ ] A user can type/speak a constraint sentence and get ranked, feasible Mumbai experiences.
- [ ] Dragging budget/time sliders instantly re-ranks results.
- [ ] Each card explains why it fits.
- [ ] Tapping a card opens detail + AI guide chat.
- [ ] Live weather banner adapts recommendations.
- [ ] README documents setup, stack, and demo fallbacks.
- [ ] Full end-to-end rehearsal completed on actual or equivalent network.
