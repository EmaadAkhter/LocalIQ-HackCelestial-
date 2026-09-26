# LocalIQ

> Not “what’s nearby” — **what you can actually experience right now.**

LocalIQ takes a traveller’s real constraints (time, budget, group, accessibility, location,
existing plans) and turns them into a ranked, explainable, re-rankable shortlist of *doable*
local experiences — not another generic list of places.

**Team Nexify · HackCelestial 3.0 · PS-6: Intelligent Local Discovery & Experience Platform**

---

## Architecture

- **Frontend:** Next.js 16 (App Router) + Tailwind CSS 4 + TypeScript
- **Backend:** FastAPI + SQLModel (Pydantic v2) + Uvicorn
- **Database:** SQLite (local file, no server process)
- **LLM:** Local Ollama for on-device inference (constraint parsing + AI guide chat)
- **Maps:** Google Maps JavaScript API (client-side only)
- **Weather:** Open-Meteo (no API key)
- **Tunnel:** Cloudflare Tunnel (`cloudflared`) for the public demo

Everything runs on your machine and is exposed publicly through a single tunnel.

## Repository structure

```text
localIQ/
├── README.md
├── PLAN.md
├── Makefile
├── .gitignore
│
├── backend/
│   ├── main.py
│   ├── requirements.txt
│   ├── .env.example
│   ├── data/
│   │   └── mumbai_experiences.json
│   └── app/
│       ├── models.py
│       ├── database.py
│       ├── seed.py
│       ├── services/
│       │   ├── recommender.py
│       │   ├── weather.py
│       │   └── llm.py
│       └── api/v1/
│           ├── experiences.py
│           ├── recommendations.py
│           ├── guides.py
│           ├── parse.py
│           ├── chat.py
│           └── weather.py
│
├── frontend/
│   ├── package.json
│   ├── next.config.ts
│   ├── tsconfig.json
│   └── src/
│       ├── app/          # layout, page, global styles
│       ├── components/   # forms, results, experience, layout
│       ├── hooks/        # useRecommendations, useSpeech, useWeather
│       ├── lib/api/      # API client
│       ├── store/        # client state
│       └── types/        # shared types
│
└── scripts/
    └── dev.sh
```

## Prerequisites

- Node.js 20+ and npm
- Python 3.11+
- [Ollama](https://ollama.com/) (local LLM)
- [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) (public demo)

## Setup

```bash
# Backend
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # then edit if needed

# Frontend
cd ../frontend
npm install

# Local LLM
ollama pull llama3.2:3b
ollama run llama3.2:3b "Say hello"   # sanity check
```

## Development commands

```bash
make install    # install backend + frontend dependencies
make dev        # run frontend + backend together
make backend    # run backend only (uvicorn on :8000)
make frontend   # run frontend only (next dev on :3000)
make lint       # lint backend + frontend
make typecheck  # typecheck backend + frontend
make tunnel     # expose the app publicly (Cloudflare Tunnel)
```

## Deployment (Cloudflare Tunnel)

Self-hosting means **your laptop must stay awake and online** for the whole judging window.
Disable sleep, keep the charger plugged in, and run the tunnel in a persistent session
(`tmux`/`screen`) so closing a terminal does not kill the demo.

```bash
cloudflared tunnel --url http://localhost:3000
```

Keep a `localhost` fallback ready in case the tunnel drops mid-pitch.

## Demo reliability

- The dataset is **seeded locally** — never depend on a live external API during the pitch.
- Constraint parsing and guide chat fall back to heuristics / canned responses if the local
  model is slow or unavailable.
- Weather and maps are progressive enhancements, not hard dependencies.

## Current status

> Initial monorepo scaffold. Business logic, recommendation algorithms, database models, AI
> integrations, weather services, APIs, and UI screens are added in the phases described in
> [`PLAN.md`](./PLAN.md).
