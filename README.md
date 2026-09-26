# LocalIQ

LocalIQ is an AI-powered local experience discovery platform that helps users find hyper-local, personalized recommendations for places, events, and activities in their city. It combines real-time data (weather, events), local knowledge, and LLMs to generate contextual, explainable suggestions.

## Architecture

- **Frontend**: Next.js 16 with Tailwind CSS 4
- **Backend**: FastAPI with Python
- **Database**: SQLite (via SQLModel)
- **LLM**: Local Ollama for on-device inference

## Repository Structure

```text
localiq/
├── README.md
├── .gitignore
├── Makefile
│
├── backend/
│   ├── main.py
│   ├── requirements.txt
│   ├── .env.example
│   │
│   ├── data/
│   │   └── mumbai_experiences.json
│   │
│   └── app/
│       ├── __init__.py
│       ├── models.py
│       ├── database.py
│       ├── seed.py
│       │
│       ├── services/
│       │   ├── __init__.py
│       │   ├── recommender.py
│       │   ├── weather.py
│       │   └── llm.py
│       │
│       └── api/
│           ├── __init__.py
│           └── v1/
│               ├── __init__.py
│               ├── experiences.py
│               ├── recommendations.py
│               ├── guides.py
│               ├── parse.py
│               ├── chat.py
│               └── weather.py
│
├── frontend/
│   ├── package.json
│   ├── next.config.ts
│   ├── tsconfig.json
│   ├── postcss.config.mjs
│   │
│   └── src/
│       ├── app/
│       │   ├── layout.tsx
│       │   ├── page.tsx
│       │   └── globals.css
│       │
│       ├── components/
│       │   ├── layout/
│       │   │   └── Header.tsx
│       │   ├── forms/
│       │   │   └── ConstraintForm.tsx
│       │   ├── results/
│       │   │   ├── RecommendationCard.tsx
│       │   │   └── RecommendationList.tsx
│       │   └── experience/
│       │       ├── ExperienceDetail.tsx
│       │       ├── GuidePanel.tsx
│       │       └── AIChat.tsx
│       │
│       ├── hooks/
│       │   ├── useRecommendations.ts
│       │   ├── useSpeech.ts
│       │   └── useWeather.ts
│       │
│       ├── lib/
│       │   └── api/
│       │       └── client.ts
│       │
│       ├── store/
│       │   └── appStore.ts
│       │
│       └── types/
│           └── feasibility.ts
│
└── scripts/
    └── dev.sh
```

## Development Commands

```bash
# Install dependencies
make install

# Start development servers (frontend + backend)
make dev

# Create tunnel for external access
make tunnel

# Run backend only
make backend

# Run frontend only
make frontend

# Lint and typecheck
make lint
make typecheck
```

## Current Status

> **Note**: This commit contains only the initial project scaffold. Implementation of business logic, recommendation algorithms, database models, AI integrations, weather services, APIs, UI screens, and external integrations will be added in subsequent phases.