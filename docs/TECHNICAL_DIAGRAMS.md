# LocalIQ — Comprehensive Technical Architecture & Engineering Diagrams

This document contains the complete set of architectural, system, infrastructure, data model (EER), algorithmic, and operational diagrams for the **LocalIQ Intelligent Local Discovery & Experience Platform**.

All diagrams are authored in standard [Mermaid.js](https://mermaid.js.org/) syntax with strict adherence to system implementation details found in the codebase.

---

## Table of Contents
1. [System Context & Container Architecture (C4 Level 1 & 2)](#1-system-context--container-architecture-c4-level-1--2)
2. [Infrastructure & Network Topology](#2-infrastructure--network-topology)
3. [Kubernetes Production Deployment Topology](#3-kubernetes-production-deployment-topology)
4. [Complete Enhanced Entity-Relationship (EER) Diagram](#4-complete-enhanced-entity-relationship-eer-diagram)
5. [Recommendation Engine & Feasibility Pipeline](#5-recommendation-engine--feasibility-pipeline)
6. [AI Travel Buddy / Agentic Execution Loop](#6-ai-travel-buddy--agentic-execution-loop)
7. [Discovery & Web Scraper Pipeline (SearXNG + LLM)](#7-discovery--web-scraper-pipeline-searxng--llm)
8. [Guide Marketplace & Trip Lifecycle State Machine](#8-guide-marketplace--trip-lifecycle-state-machine)
9. [Group Decision Consensus Engine (Borda Voting)](#9-group-decision-consensus-engine-borda-voting)
10. [Frontend (Flutter) Clean Architecture](#10-frontend-flutter-clean-architecture)
11. [CI/CD Pipeline (Jenkins Automation)](#11-cicd-pipeline-jenkins-automation)
12. [Security, Auth & Threat Model](#12-security-auth--threat-model)

---

## 1. System Context & Container Architecture (C4 Level 1 & 2)

LocalIQ connects travellers, local guides, and curators through a single ingress gateway, orchestrating self-hosted models, relational/vector databases, and external contextual APIs.

```mermaid
flowchart TB
    subgraph Clients["Client Applications"]
        F_WEB["Flutter Web Client\n(Browser SPA)"]
        F_MOB["Flutter Mobile App\n(iOS & Android)"]
        LEG_WEB["Legacy Web Client\n(Next.js Dev Reference)"]
        EXT_DEV["Developer / Teammate\n(API & Shared LLM Client)"]
    end

    subgraph Edge["Edge Layer (Public Ingress)"]
        CF["Cloudflare Edge Network\n(TLS Termination / DDoS Protection)"]
        CFT["cloudflared Tunnel Daemon\n(localiq.tavesglobal.com)"]
    end

    subgraph Gateway["Gateway & Ingress Layer (:8080)"]
        CADDY["Caddy v2 Edge Reverse Proxy\n- Gzip & Zstd compression\n- Route splitting"]
        NGINX["nginx:1.27-alpine\n(Static Flutter SPA Bundle Host)"]
        KONG["Kong 3.9 API Gateway (DB-less)\n- /api/v1/* Routing\n- /llm/* Key-Auth Plugin"]
    end

    subgraph Backend_Layer["Application Core"]
        FASTAPI["FastAPI 0.115+ Backend Application\n(Python 3.12, Uvicorn, Non-Root)"]
        
        subgraph Internal_Services["Application Services"]
            REC_SRV["Recommender Service\n(Feasibility + Ranking)"]
            SEM_SRV["Semantic Search Service\n(Vector Similarity)"]
            LLM_SRV["LLM & Agent Service\n(ReAct Travel Buddy)"]
            DISC_SRV["Discovery Pipeline\n(SearXNG Scraper + LLM)"]
            GUIDE_SRV["Guide Marketplace & Ops\n(Booking & Driver GPS)"]
            TASTE_SRV["Personalization & Taste Engine\n(Implicit/Explicit Signals)"]
            RIGHT_SRV["Right-Now Live Context Engine\n(Weather + Density + Time)"]
        end
    end

    subgraph Storage_Layer["Data & Persistence Layer"]
        PG[("PostgreSQL 16 + pgvector\n(36 Relational Tables +\n768-dim Vector Embeddings)")]
        S3[("Adobe S3Mock / MinIO\n(Object Store for Media & IDs)")]
    end

    subgraph AI_Engines["AI & Inference Engines"]
        OLLAMA["Local Ollama Daemon\n(Llama 3.2:3b / Qwen 2.5:7b\nNomic-embed-text)"]
        GROQ["Groq Cloud API (Optional)\n(Llama-3.3-70b-versatile)"]
        SEARXNG["SearXNG Meta-Search Engine\n(Self-Hosted Privacy Search)"]
    end

    subgraph External_APIs["External Context Providers"]
        METEO["Open-Meteo API\n(Real-Time Mumbai Weather)"]
        GMAPS["Google Maps Platform\n(Places API & Routes API)"]
        RESEND["Resend Email API\n(Transaction & Verification Mails)"]
    end

    %% Client traffic
    F_WEB -->|HTTPS| CF
    F_MOB -->|HTTPS| CF
    LEG_WEB -->|HTTP| CADDY
    EXT_DEV -->|"HTTPS (apikey)"| CF
    CF --> CFT
    CFT --> CADDY

    %% Caddy Routing
    CADDY -->|"Root / (Default)"| NGINX
    CADDY -->|"/api/*"| KONG
    CADDY -->|"/llm/*"| KONG
    CADDY -->|"/docs, /redoc, /readyz"| FASTAPI
    CADDY -->|"/static/*, /media/*"| FASTAPI

    %% Kong Routing
    KONG -->|"Reverse Proxy /api/*"| FASTAPI
    KONG -->|"Key-Auth Protected /llm/*"| OLLAMA

    %% Backend Connections
    FASTAPI --> REC_SRV
    FASTAPI --> SEM_SRV
    FASTAPI --> LLM_SRV
    FASTAPI --> DISC_SRV
    FASTAPI --> GUIDE_SRV
    FASTAPI --> TASTE_SRV
    FASTAPI --> RIGHT_SRV

    FASTAPI -->|psycopg2 / SQLModel| PG
    FASTAPI -->|boto3 S3 API| S3
    FASTAPI -->|HTTP REST| OLLAMA
    FASTAPI -.->|Fallback / Hosted| GROQ
    FASTAPI -->|HTTP JSON API| SEARXNG
    FASTAPI -->|REST API| METEO
    FASTAPI -->|SDK| GMAPS
    FASTAPI -->|REST API| RESEND
```

---

## 2. Infrastructure & Network Topology

This diagram details the Docker Compose network architecture, container resource caps, volume bindings, and inter-service dependencies.

```mermaid
graph TD
    subgraph Host["Host Machine (macOS / Linux Development Node)"]
        OLLAMA_HOST["Host Ollama Service\n(Port :11434)\nModels: nomic-embed-text, llama3.2:3b"]
        CLOUDFLARE_HOST["cloudflared tunnel agent\n(local process / tunnel runner)"]
    end

    subgraph DockerBridge["Docker Network: localiq (Bridge)"]
        subgraph IngressGroup["Ingress & Proxy Services"]
            CADDY_CONT["caddy:2-alpine\nPorts: 8080:80\nLimits: 64MB RAM\nVolume: gateway/caddy/Caddyfile"]
            NGINX_CONT["nginx:1.27-alpine\nPorts: Internal 80\nLimits: 64MB RAM\nVolume: flutter-web build"]
            KONG_CONT["kong:3.9 (DB-less)\nPorts: Internal 8000, 8001\nLimits: 640MB RAM\nVolume: gateway/kong/kong.yml"]
        end

        subgraph CoreGroup["Application Services"]
            BACKEND_CONT["backend:local (FastAPI)\nLimits: 384MB RAM\nEnv: Python 3.12, Uvicorn\nExtra Host: host.docker.internal"]
        end

        subgraph DataGroup["Data & Storage Services"]
            PG_CONT["pgvector/pgvector:pg16\nLimits: 256MB RAM\nBuffer: shared_buffers=64MB\nMax Conn: 50\nVolume: postgres-data"]
            S3_CONT["adobe/s3mock:latest\nPorts: 9000:9090\nLimits: 256MB RAM\nVolume: /tmp/s3root"]
            SEARXNG_CONT["searxng/searxng:latest\nProfile: discovery\nPorts: 8888:8080\nLimits: 256MB RAM\nVolume: searxng/settings.yml"]
        end
    end

    %% Network Connections
    CLOUDFLARE_HOST -->|"Forward to :8080"| CADDY_CONT
    CADDY_CONT -->|"Internal Proxy"| NGINX_CONT
    CADDY_CONT -->|"Internal Proxy"| KONG_CONT
    CADDY_CONT -->|"Direct Health and Media"| BACKEND_CONT

    KONG_CONT -->|"Route /api/*"| BACKEND_CONT
    KONG_CONT -->|"Route /llm/* via host"| OLLAMA_HOST

    BACKEND_CONT -->|Depends on Healthy| PG_CONT
    BACKEND_CONT -->|Depends on Started| S3_CONT
    BACKEND_CONT -.->|Optional Discovery Service| SEARXNG_CONT
    BACKEND_CONT -->|"host.docker.internal:11434"| OLLAMA_HOST

    classDef container fill:#1e293b,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    classDef storage fill:#0f172a,stroke:#34d399,stroke-width:2px,color:#f8fafc;
    classDef edge fill:#312e81,stroke:#818cf8,stroke-width:2px,color:#f8fafc;
    class CADDY_CONT,NGINX_CONT,KONG_CONT,BACKEND_CONT container;
    class PG_CONT,S3_CONT,SEARXNG_CONT storage;
    class OLLAMA_HOST,CLOUDFLARE_HOST edge;
```

---

## 3. Kubernetes Production Deployment Topology

The production-grade Kubernetes topology featuring the `localiq` namespace, persistent volume claims, secret bindings, and Horizontal Pod Autoscaler (HPA) targeting backend services.

```mermaid
flowchart TD
    subgraph K8S_CLUSTER["Kubernetes Cluster (Namespace: localiq)"]
        subgraph Ingress_Sub["Ingress Controller"]
            K8S_ING["Ingress / Cloudflare Tunnel Pod\n(cloudflared.yaml)"]
            CADDY_DEP["Deployment: caddy\n(Replicas: 2)\nService: caddy-svc:80"]
        end

        subgraph Services_Sub["Internal Gateways & Static"]
            KONG_DEP["Deployment: kong\n(Replicas: 2, ConfigMap: kong-declarative)\nService: kong-svc:8000"]
            FLUTTER_DEP["Deployment: flutter-web\n(Replicas: 2, nginx Alpine)\nService: flutter-web-svc:80"]
        end

        subgraph Core_Sub["Application Pods & Autoscaling"]
            BACKEND_DEP["Deployment: backend\n(Python 3.12 FastAPI)\nService: backend-svc:8000\nReadiness: /readyz\nLiveness: /healthz"]
            HPA["Horizontal Pod Autoscaler (HPA)\nMin: 2 | Max: 10\nTarget CPU Utilization: 70%"]
        end

        subgraph Config_Secrets["Configuration & State"]
            CM["ConfigMap: localiq-config\n(APP_ENV, SEARXNG_URL, CORS)"]
            SEC["Secret: localiq-secrets\n(AUTH_SECRET_KEY, DB_PASS, API_KEYS)"]
        end

        subgraph Stateful_Sub["Stateful Workloads"]
            PG_SS["StatefulSet: postgres-pgvector\nStorage: PVC 10Gi (gp3)\nService: postgres-svc:5432"]
            OLLAMA_DEP["Deployment: ollama\n(Optional node-selector / GPU)\nService: ollama-svc:11434"]
        end
    end

    K8S_ING --> CADDY_DEP
    CADDY_DEP --> FLUTTER_DEP
    CADDY_DEP --> KONG_DEP
    CADDY_DEP --> BACKEND_DEP

    KONG_DEP --> BACKEND_DEP
    KONG_DEP --> OLLAMA_DEP

    HPA -.->|Controls Replicas| BACKEND_DEP

    BACKEND_DEP --> CM
    BACKEND_DEP --> SEC
    BACKEND_DEP --> PG_SS
    BACKEND_DEP --> OLLAMA_DEP
```

---

## 4. Complete Enhanced Entity-Relationship (EER) Diagram

This diagram displays all **36 database models** across `models.py` and `models_prd.py`, their primary keys, foreign key references, and relationship cardinalities.

```mermaid
erDiagram
    %% Core Domain
    USER ||--o{ USER_SESSION : "has"
    USER ||--o{ EMAIL_VERIFICATION_TOKEN : "issues"
    USER ||--o{ NOTIFICATION : "receives"
    USER ||--o| USER_PROFILE : "profile"
    USER ||--o| EXPERIENCE_WALLET : "owns"
    USER ||--o{ EXPERIENCE_LOG : "logs"
    USER ||--o{ USER_BADGE : "earns"
    USER ||--o| USER_PROGRESS : "tracks"
    USER ||--o{ FAVORITE : "saves"
    USER ||--o{ ITINERARY : "creates"
    USER ||--o{ RECOMMENDATION_FEEDBACK : "submits"
    USER ||--o{ PREFERENCE_SIGNAL : "emits"
    USER ||--o{ USER_ACTIVITY_INTERACTION : "performs"
    USER ||--o{ CONVERSATION_SESSION : "holds"
    USER ||--o{ CONVERSATION : "participates"
    USER ||--o{ AGENT_RUN : "executes"
    USER ||--o{ ONBOARDING_SESSION : "completes"
    USER ||--o{ GROUP : "owns"
    USER ||--o{ GROUP_MEMBER : "joins"
    USER ||--o{ GROUP_VOTE : "votes"
    USER ||--o{ MEETUP_REQUEST : "requests"
    USER ||--o{ MEETUP_REVIEW : "reviews"
    USER ||--o{ MEETUP_BLOCK : "blocks"
    USER ||--o{ PACKAGE_BOOKING : "books"
    USER ||--o{ PACKAGE_REVIEW : "authors"
    USER ||--o{ GUIDE_BOOKING : "reserves"
    USER ||--o{ GUIDE_REVIEW : "rates"

    %% Experience & Guide Domain
    EXPERIENCE ||--o{ GUIDE : "associated_with"
    EXPERIENCE ||--o{ EXPERIENCE_TAG : "classified_by"
    EXPERIENCE ||--o{ ITINERARY_STOP : "included_in"
    EXPERIENCE ||--o{ FAVORITE : "saved_in"
    EXPERIENCE ||--o{ RECOMMENDATION_FEEDBACK : "rated_by"
    EXPERIENCE ||--o{ GUIDE_PACKAGE_STOP : "segment_of"
    EXPERIENCE ||--o{ AI_TIP : "has_tips"
    EXPERIENCE ||--o{ QUEST_STOP : "checkpoint_in"
    EXPERIENCE ||--o{ EXPERIENCE_LOG : "logged_in"
    EXPERIENCE ||--o{ EXPERIENCE_SESSION : "guided_in"

    TAG ||--o{ EXPERIENCE_TAG : "attached_to"
    USER_PROFILE ||--o{ USER_INTEREST : "contains"
    ITINERARY ||--o{ ITINERARY_STOP : "sequences"
    CONVERSATION ||--o{ MESSAGE : "contains"
    CONVERSATION ||--o{ AGENT_RUN : "triggers"

    %% Guide Marketplace
    GUIDE ||--o| GUIDE_PROFILE : "has_profile"
    GUIDE ||--o{ GUIDE_AVAILABILITY : "publishes"
    GUIDE ||--o{ GUIDE_PACKAGE : "offers"
    GUIDE ||--o{ PACKAGE_BOOKING : "accepts"
    GUIDE ||--o{ PACKAGE_REVIEW : "receives"
    GUIDE ||--o{ GUIDE_BOOKING : "fulfills"
    GUIDE ||--o{ GUIDE_REVIEW : "receives_reviews"
    GUIDE ||--o{ GUIDE_TRAINING : "undergoes"
    GUIDE_PACKAGE ||--o{ GUIDE_PACKAGE_STOP : "routes"
    GUIDE_PACKAGE ||--o{ PACKAGE_BOOKING : "booked_as"
    GUIDE_AVAILABILITY ||--o{ GUIDE_BOOKING : "reserves_slot"

    %% Discovery Domain
    DISCOVERY_SOURCE ||--o{ CANDIDATE_CITATION : "cites"
    SCRAPED_CANDIDATE ||--o{ CANDIDATE_CITATION : "mentions"
    SOURCE ||--o{ HIDDEN_GEM_CANDIDATE : "sources"

    %% Social & Groups
    GROUP ||--o{ GROUP_MEMBER : "members"
    GROUP ||--o{ GROUP_OPTION : "options"
    GROUP ||--o{ GROUP_VOTE : "votes"
    GROUP_OPTION ||--o{ GROUP_VOTE : "receives_votes"
    MEETUP_REQUEST ||--o{ MEETUP_MATCH : "forms"
    MEETUP_MATCH ||--o{ MEETUP_REVIEW : "generates"

    %% Quests & Gamification
    QUEST ||--o{ QUEST_STOP : "composed_of"
    QUEST ||--o{ QUEST_RUN : "played_in"
    BADGE ||--o{ USER_BADGE : "cataloged_as"

    %% Entity Details
    USER {
        int id PK
        string email UK
        string password_hash
        string trust_tier "basic, standard, trusted"
        string tier "free, plus, pro"
        string home_city
        json taste_profile_vector
        datetime created_at
        datetime updated_at
    }

    EXPERIENCE {
        int id PK
        string name
        string category
        float lat
        float lng
        int avg_cost
        int duration_min
        string open_time
        string close_time
        float rating
        float local_gem_score
        vector embedding
        json tags
        json accessibility_flags
        json right_now_context_json
        float right_now_score
    }

    TAG {
        int id PK
        string name UK
        string category
        string facet_type "user_facing, internal, composite"
        float weight
    }

    EXPERIENCE_TAG {
        int id PK
        int experience_id FK
        int tag_id FK
        float confidence
        string source
    }

    GUIDE {
        int id PK
        int experience_id FK
        string name
        int rate_per_hour
        float rating
        string verification_status
        json languages
    }

    GUIDE_PACKAGE {
        int id PK
        int guide_id FK
        string title
        string pickup_type
        float total_duration_hours
        int price_per_person
        json inclusions
    }

    PACKAGE_BOOKING {
        int id PK
        string booking_ref UK
        int user_id FK
        int guide_id FK
        int package_id FK
        string status "requested, accepted, confirmed, completed, cancelled"
        float driver_lat
        float driver_lng
        datetime driver_updated_at
    }

    ITINERARY {
        int id PK
        int user_id FK
        string name
        int total_duration_min
        int total_cost
        string share_token UK
    }

    SCRAPED_CANDIDATE {
        int id PK
        string raw_title
        string url
        string area
        json extracted_data
        float llm_confidence
        string status "pending, approved, rejected"
    }

    QUEST {
        int id PK
        string code UK
        string title
        string difficulty
        int xp_reward
        int estimated_minutes
    }

    GROUP {
        int id PK
        int owner_id FK
        string name
        string status "collecting_preferences, collecting_votes, locked"
        json final_plan
    }
```

---

## 5. Recommendation Engine & Feasibility Pipeline

LocalIQ implements a strict **feasibility-first** algorithmic architecture. No experience is scored or ranked unless it passes all hard real-world constraints.

```mermaid
flowchart TD
    START([User Constraint Input]) --> GEO[0. Resolve Location Anchor\ne.g. Bandra to 19.0596, 72.8295]

    GEO --> STAGE1[Phase A: Feasibility Filtering Gates]

    subgraph PhaseA["Phase A — Hard Feasibility Gates"]
        F1{"1. Distance Gate\nDistance > 30km?"}
        F2{"2. Travel Time Heuristic\nTravel + Visit + 20min buffer > Time Window?"}
        F3{"3. Budget Gate\navg_cost > budget_inr?"}
        F4{"4. Operating Hours Gate\nVenue open during needed window?"}
        F5{"5. Accessibility Gate\nFlags match requested capabilities?"}
        F6{"6. Tag Exclusion Gate\nHas tags in excluded list?"}

        F1 -- Yes --> DROP1[REJECT: Too Far Away]
        F2 -- Yes --> DROP2[REJECT: Time Infeasible]
        F3 -- Yes --> DROP3[REJECT: Exceeds Budget]
        F4 -- No --> DROP4[REJECT: Venue Closed]
        F5 -- Missing --> DROP5[REJECT: Missing Accessibility]
        F6 -- Yes --> DROP6[REJECT: Excluded Tag]
    end

    STAGE1 --> F1
    F1 -- No --> F2
    F2 -- No --> F3
    F3 -- No --> F4
    F4 -- Yes --> F5
    F5 -- Pass --> F6
    F6 -- Pass --> FEASIBLE_SET[(M Feasible Candidates Retained)]

    FEASIBLE_SET --> STAGE2[Phase B: Multi-Factor Weighted Scoring]

    subgraph PhaseB["Phase B — Multi-Factor Weighted Scoring"]
        SC_INT["Interest Match (0..30 pts)"]
        SC_TIME["Time Window Fit (0..20 pts)"]
        SC_BUDGET["Budget Ratio Fit (0..15 pts)"]
        SC_DIST["Proximity Score (0..15 pts)"]
        SC_RATING["Rating Score (0..12 pts)"]
        SC_GEM["Local Gem Score (0..8 pts)"]
        SC_WEATHER["Weather Suitability (-6..+6 pts)"]
        SC_FEEDBACK["User Community Feedback (-8..+8 pts)"]
        SC_SEM["Semantic Cosine Bonus (0..5 pts)"]
        SC_TASTE["Taste Profile Vector Dot-Product"]
    end

    STAGE2 --> SC_INT
    STAGE2 --> SC_TIME
    STAGE2 --> SC_BUDGET
    STAGE2 --> SC_DIST
    STAGE2 --> SC_RATING
    STAGE2 --> SC_GEM
    STAGE2 --> SC_WEATHER
    STAGE2 --> SC_FEEDBACK
    STAGE2 --> SC_SEM
    STAGE2 --> SC_TASTE

    SC_INT --> AGG[Sum Weighted Components]
    SC_TIME --> AGG
    SC_BUDGET --> AGG
    SC_DIST --> AGG
    SC_RATING --> AGG
    SC_GEM --> AGG
    SC_WEATHER --> AGG
    SC_FEEDBACK --> AGG
    SC_SEM --> AGG
    SC_TASTE --> AGG

    AGG --> EXPLAIN[Deterministic Explainability Engine\nZero Hallucination Reason Templates]

    EXPLAIN --> OUTPUT([Ranked Shortlist Response])
```

---

## 6. AI Travel Buddy / Agentic Execution Loop

The conversational Travel Buddy operates an agentic ReAct loop (Reasoning + Tool Execution) backed by Ollama (or Groq), persisted in database conversation threads.

```mermaid
sequenceDiagram
    autonumber
    actor User as Traveller (Flutter Client)
    participant API as FastAPI Router (/api/v1/agent)
    participant Svc as Agent Service (app/services/agent.py)
    participant Tools as Agent Tools (app/services/agent_tools.py)
    participant LLM as Inference Engine (Ollama / Groq)
    participant DB as PostgreSQL Database

    User->>API: POST /api/v1/agent/chat (message, conversation_id)
    API->>DB: Load conversation history & taste profile
    API->>Svc: Execute Agent Loop
    Svc->>DB: Create AgentRun (status="running")

    loop ReAct Tool Execution Loop (Max 5 Turns)
        Svc->>LLM: Prompt (System Context, User Intent, Tools Schema, History)
        LLM-->>Svc: Tool Call Intent (e.g., search_places, get_weather)
        
        alt LLM requests Tool Execution
            Svc->>Tools: Dispatch Tool (e.g. get_weather)
            Tools->>Tools: Query DB / Internal Recommender / Open-Meteo
            Tools-->>Svc: Tool Output Result (JSON)
            Svc->>DB: Append tool message to AgentRun.tool_calls_json
        else LLM emits Final Message
            LLM-->>Svc: Final Assistant Content
        end
    end

    Svc->>DB: Update AgentRun (status="completed", result)
    Svc->>DB: Persist Message(role="assistant", content)
    Svc-->>API: Response (Answer, Used Tools, Suggestions)
    API-->>User: Rendered Stream / JSON Response
```

---

## 7. Discovery & Web Scraper Pipeline (SearXNG + LLM)

LocalIQ continuously discovers hidden spots by searching open web resources via SearXNG, scraping pages, extracting structured JSON with local LLMs, and routing candidates to admin moderation.

```mermaid
flowchart TD
    START([Admin / Discovery Trigger]) --> SEARX[Query SearXNG Meta-Search\nEngines: Google, Bing, DuckDuckGo, Reddit]
    
    SEARX --> RESULTS[Extract Ranked Result URLs\nFilter Out Low-Quality Domains]

    RESULTS --> SCRAPE{Fetch Webpage HTML\nHTTP Client with Timeout}

    SCRAPE -- Bot Blocked / 403 / Timeout --> FALLBACK_SNIP[Use SearXNG Search Snippets\nas Source Text]
    SCRAPE -- 200 OK --> CLEAN_HTML[Strip Scripts, CSS, Nav\nExtract Clean Article Body]

    FALLBACK_SNIP --> LLM_EXTRACT{Local LLM Extraction Mode\ndiscovery_use_llm=true?}
    CLEAN_HTML --> LLM_EXTRACT

    LLM_EXTRACT -- Yes (Ollama llama3.2:3b) --> PROMPT_LLM[Prompt Local LLM:\nConstrained to Tag Taxonomy\nand Known Mumbai Areas]
    LLM_EXTRACT -- No / LLM Unavailable --> HEURISTIC[Deterministic Heuristic Extractor:\nRegex Entity Parsing & Area Matching]

    PROMPT_LLM --> VALIDATE{Validate JSON & Schema}
    VALIDATE -- Valid JSON --> CANDIDATE_OBJ[Construct ScrapedCandidate Model]
    VALIDATE -- Parse Failure --> HEURISTIC
    HEURISTIC --> CANDIDATE_OBJ

    CANDIDATE_OBJ --> CITATION[Attach Source Provenance:\nURL, Source, Quote, Sentiment]

    CITATION --> DB_PENDING[Insert into PostgreSQL:\nscraped_candidates and citations]

    DB_PENDING --> MODERATION{Admin Curation Portal}

    MODERATION -- Approve --> PROMOTED[Promote to Curated Catalog:\nexperiences, tags, vector embedding]
    MODERATION -- Reject --> REJECTED[Mark status='rejected']
```

---

## 8. Guide Marketplace & Trip Lifecycle State Machine

A state machine managing guide package bookings, from initial guest request through driver GPS polling to tour completion and verification.

```mermaid
stateDiagram-v2
    [*] --> Requested: Traveller Books Package
    
    Requested --> Accepted: Guide Accepts Booking
    Requested --> Declined: Guide Declines with Reason
    Requested --> Cancelled: Traveller Cancels

    Declined --> [*]
    Cancelled --> [*]

    Accepted --> Confirmed: Payment Simulated and Escrow Secured
    Accepted --> Cancelled: Traveller or Guide Cancels

    Confirmed --> InProgress: Trip Started

    InProgress --> Completed: Tour Concluded
    InProgress --> Cancelled: Emergency Tour Abort

    Completed --> Reviewed: Guest Submits Review and Rating
    Reviewed --> XP_Awarded: Update Guide Profile with XP
    XP_Awarded --> [*]
```

---

## 9. Group Decision Consensus Engine (Borda Voting)

When multiple travellers plan an outing together, LocalIQ resolves divergent preferences using a multi-criteria group decision engine with **Borda Count Ranked-Choice Voting**.

```mermaid
flowchart TD
    G1[Group Creator Initializes Outing] --> G2[Invite Group Members via Link]
    
    G2 --> G3[Members Submit Individual Preferences:\nBudget, Availability, Interests, Accessibility]
    
    G3 --> G4{All Members Submitted\nor Deadline Met?}
    G4 -- No --> G3
    G4 -- Yes --> G5[Generate Feasible Joint Plans\nIntersect Constraints via Recommender]

    G5 --> G6[Formulate Top 3-5 Diverse Candidate Options]

    G6 --> G7[Ballot Stage: Ranked-Choice Voting\nMembers rank options 1st, 2nd, 3rd]

    G7 --> G8[Borda Count Resolution Algorithm\nRank 1 = N points, Rank 2 = N-1 points]

    G8 --> G9{Tie Breaker Needed?}
    G9 -- Yes --> G10[Apply Safety and Accessibility Weight]
    G9 -- No --> G11[Declare Winning Itinerary Option]
    G10 --> G11

    G11 --> G12[Lock Group Plan\nAuto-Generate Itinerary in DB]
    G12 --> G13([Push Notifications to Members with Final Plan])
```

---

## 10. Frontend (Flutter) Clean Architecture

The Flutter client uses a **Feature-Driven Clean Architecture** to support Web, iOS, and Android targets from a unified codebase.

```mermaid
graph TB
    subgraph Presentation_Layer["Presentation Layer (Flutter UI)"]
        UI_VIEWS["Feature Views / Screens\nExplorer, RecommendationSheet, MapView,\nCompanionChat, GroupVoting, GuideMarketplace"]
        UI_WIDGETS["Reusable Components\nExperienceCard, FeasibilityPill, WeatherBadge,\nDriverTrackerSheet, StarRating"]
        CONTROLLERS["State Management Controllers\nRiverpod Notifiers / Bloc / Cubit"]
    end

    subgraph Domain_Layer["Domain Layer (Business Logic)"]
        USE_CASES["Application Use Cases\nFetchRecommendations, ParseIntent,\nBookGuide, VoteGroupOption"]
        ENTITIES["Domain Entities & Value Objects\nExperience, FeasibleWindow, UserTaste,\nItineraryStop, GuideProfile"]
    end

    subgraph Data_Layer["Data Layer (Networking & Storage)"]
        REPOS["Repository Implementations\nExperienceRepository, AuthRepository,\nLocationRepository, AgentRepository"]
        DATA_SOURCES_REMOTE["Remote Data Sources\nDio HTTP Client, SSE EventSource"]
        DATA_SOURCES_LOCAL["Local Data Sources\nFlutterSecureStorage, SharedPreferences Cache,\nSQLite / Hive Offline Database"]
    end

    UI_VIEWS --> CONTROLLERS
    UI_WIDGETS --> CONTROLLERS
    CONTROLLERS --> USE_CASES
    USE_CASES --> ENTITIES
    USE_CASES --> REPOS
    REPOS --> DATA_SOURCES_REMOTE
    REPOS --> DATA_SOURCES_LOCAL
    DATA_SOURCES_REMOTE -->|"HTTP / JSON"| API_EDGE["Caddy Edge / Kong Gateway"]
```

---

## 11. CI/CD Pipeline (Jenkins Automation)

Automated continuous integration pipeline configured via `Jenkinsfile` and Jenkins Configuration as Code (JCasC), enforcing an 80% backend test coverage gate.

```mermaid
flowchart LR
    DEV([Developer Commit]) -->|Git Push| GITHUB[GitHub Repository]
    GITHUB -->|Webhook Trigger| JENKINS[Self-Hosted Jenkins :8081\nJCasC Configured]

    subgraph Pipeline["Jenkins CI Pipeline Execution"]
        ST1["Stage 1: Checkout\nSCM Git Checkout"]
        ST2["Stage 2: Code Quality\nflake8 & black checks\nSecurity linting"]
        ST3["Stage 3: Unit & Integration Tests\npytest with pgvector/SQLite\nEnforce 80% Coverage Gate"]
        ST4["Stage 4: Multi-Stage Docker Build\nBuild FastAPI & Flutter Web Images\nNon-Root Security Hardening"]
        ST5["Stage 5: Container Smoke Test\nRun ephemeral containers\nVerify /healthz & /readyz"]
        ST6["Stage 6: Artifact Delivery\nPush images / Deploy trigger"]
    end

    JENKINS --> ST1
    ST1 --> ST2
    ST2 --> ST3
    ST3 -- "Coverage < 80%" --> FAIL([Pipeline Failed: Abort])
    ST3 -- "Coverage >= 80%" --> ST4
    ST4 --> ST5
    ST5 --> ST6
    ST6 --> SUCCESS([Build Passed & Certified])
```

---

## 12. Security, Auth & Threat Model

The multi-layered defence-in-depth model protecting users, database records, and self-hosted AI compute.

```mermaid
flowchart TD
    subgraph Perimeter["1. Perimeter Defence (Public Edge)"]
        CF_IN["Cloudflare Edge\n- DDoS Protection\n- TLS 1.3 Termination\n- Bot Heuristics"]
        TUNNEL["Named Cloudflare Tunnel\n(localiq.tavesglobal.com)"]
    end

    subgraph Edge_Gateway["2. Gateway Security Layer"]
        CADDY_SEC["Caddy Proxy\n- Strict Method & Path Routing\n- Hiding Internal Ports (:8000, :5432, :11434)"]
        KONG_SEC["Kong API Gateway\n- /llm/* Protected by key-auth Plugin\n- IP Rate Limiting (e.g. 100 req/min)"]
    end

    subgraph App_Security["3. Application Security (FastAPI Core)"]
        LOCKOUT["Brute-Force Lockout Middleware\nMax 5 failed logins -> 15 min lock"]
        AUTH_TOK["Session & Token Security\n- PBKDF2-SHA256 Password Hashing\n- Cryptographically Random Tokens\n- Stored ONLY as SHA-256 Hashes in DB"]
        CORS_FILTER["Explicit CORS Allow-List\nNo Wildcards allowed in Production"]
        ERR_MASK["Unified Error Schema\nStack traces masked, no internal leakage"]
    end

    subgraph Data_Security["4. Database & Storage Layer"]
        SQL_PARAM["SQLModel / SQLAlchemy ORM\nStrict Parameterized Queries\n(Zero SQL Injection)"]
        NON_ROOT["Non-Root Container Execution\n(UID 10001, read-only root filesystems)"]
        SECRETS["Secrets-from-File / Environment Isolation\nAUTH_SECRET_KEY validation on boot"]
    end

    CF_IN --> TUNNEL
    TUNNEL --> CADDY_SEC
    CADDY_SEC --> KONG_SEC
    KONG_SEC --> LOCKOUT
    LOCKOUT --> AUTH_TOK
    AUTH_TOK --> CORS_FILTER
    CORS_FILTER --> ERR_MASK
    ERR_MASK --> SQL_PARAM
    SQL_PARAM --> NON_ROOT
    NON_ROOT --> SECRETS
```

---

*Diagrams generated for LocalIQ (Team Nexify · HackCelestial 3.0 · PS-6: Intelligent Local Discovery & Experience Platform).*
