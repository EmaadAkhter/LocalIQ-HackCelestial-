#!/usr/bin/env python3
"""Build LocalIQ's Nugen alignment corpus.

Nugen aligns a base model on *documents*. We upload two plain-text corpora, one
per task, each holding many instruction/response pairs:

  Task A — constraint extraction: free text (English / Hinglish / code-mixed)
           -> strict JSON (location, time_minutes, budget_inr, interests,
              preferences).
  Task B — explanation generation: experience + constraints + weather context
           -> 2-4 line "why this fits" copy in LocalIQ's house style.

The corpus is composed from templates across every neighbourhood, budget band
and language register LocalIQ actually sees. It is deliberately synthetic-but-
realistic, not scraped. Run:

    python scripts/build_nugen_dataset.py

Writes:
    data/nugen/constraint_extraction.txt
    data/nugen/explanation_generation.txt
    data/nugen/constraint_extraction.eval.jsonl   (held-out)
    data/nugen/explanation_generation.eval.jsonl  (held-out)
"""

from __future__ import annotations

import json
import random
from pathlib import Path

random.seed(20260927)

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "nugen"

# ---------------------------------------------------------------------------
# Vocabulary
# ---------------------------------------------------------------------------

AREAS = [
    "Bandra", "Colaba", "Dadar", "Juhu", "Andheri", "Powai", "Versova",
    "Churchgate", "Marine Lines", "Mahim", "Parel", "Wadala", "Sion", "Kurla",
    "Chembur", "Byculla", "Fort", "CSMT", "Crawford Market", "Kala Ghoda",
    "Lower Parel", "Worli", "Malabar Hill", "Girgaon", "Matunga", "Vile Parle",
    "Santacruz", "Khar", "Oshiwara", "Goregaon",
]

INTERESTS = [
    "food", "culture", "history", "art", "nature", "heritage", "nightlife",
    "shopping", "wellness", "adventure", "local life",
]

PREFERENCES = [
    "local", "indoor", "outdoor", "quiet", "budget", "family-friendly",
    "accessible", "quick", "hidden", "popular", "rooftop", "waterfront",
    "vegetarian", "late-night", "morning", "sunset",
]

TIMES = [30, 45, 60, 90, 120, 150, 180, 240, 300, 360]
BUDGETS = [0, 200, 300, 500, 800, 1000, 1500, 2000, 3000, 5000]

GROUP_HINTS = {
    "solo": ["solo", "by myself", "alone", "akela"],
    "couple": ["with my partner", "as a couple", "date", "partner ke saath"],
    "friends": ["with friends", "doston ke saath", "friends ke saath", "group of friends"],
    "family": ["with my family", "family ke saath", "with kids", "bacchon ke saath"],
}

HINDI_TIME = {
    30: "aadha ghanta", 60: "ek ghanta", 90: "dedh ghanta", 120: "do ghante",
    150: "dhai ghante", 180: "teen ghante", 240: "char ghante", 300: "paanch ghante",
}

FILLERS_EN = ["", "please", "if possible", "ideally", "something like", "you know"]
FILLERS_HI = ["", "please", "agar possible ho", "koi acha sa", "matlab"]


# ---------------------------------------------------------------------------
# Task A — constraint extraction
# ---------------------------------------------------------------------------


def _json_a(area, minutes, budget, interests, prefs):
    return {
        "location": area,
        "time_minutes": minutes,
        "budget_inr": budget,
        "interests": interests,
        "preferences": prefs,
    }


def _pick(seq, k):
    k = max(1, min(k, len(seq)))
    return random.sample(seq, k)


def example_en(area, minutes, budget, interests, prefs, group):
    filler = random.choice(FILLERS_EN)
    gh = {"solo": "1 person", "couple": "2 of us", "friends": "a group of 4",
          "family": "a family of 4"}[group]
    budget_txt = f"₹{budget}" if budget > 0 else "as cheap as possible"
    return (
        f"I have {minutes // 60} hours in {area} with a budget of {budget_txt}. "
        f"There are {gh} and we want {', '.join(interests)} that is "
        f"{', '.join(prefs)}. {filler}".strip()
    )


def example_hi(area, minutes, budget, interests, prefs, group):
    filler = random.choice(FILLERS_HI)
    t = HINDI_TIME.get(minutes, f"{minutes} minute")
    budget_txt = f"budget ₹{budget}" if budget > 0 else "budget kam hai"
    gh = {"solo": "main akela", "couple": "hum dono",
          "friends": "hum dost", "family": "hum family ke saath"}[group]
    return (
        f"Mere paas {t} hain {area} mein, {budget_txt}, "
        f"{gh} ko {', '.join(interests)} chahiye jo {', '.join(prefs)} ho. {filler}".strip()
    )


def example_mixed(area, minutes, budget, interests, prefs, group):
    gh = {"solo": "me alone", "couple": "we two", "friends": "4 log",
          "family": "family ke saath"}[group]
    budget_txt = f"budget ₹{budget}" if budget > 0 else "cheap only"
    return (
        f"{minutes} minutes in {area}, {budget_txt}, {gh} — "
        f"{', '.join(interests)} chahiye, {', '.join(prefs)}."
    )


def build_task_a(n=420):
    """Return (train_pairs, eval_pairs)."""
    rows = []
    # Guarantee full area coverage first, then keep sampling for volume.
    for area in AREAS:
        rows.append((area, random.choice(TIMES), random.choice(BUDGETS),
                     _pick(INTERESTS, random.randint(1, 3)),
                     _pick(PREFERENCES, random.randint(1, 2)),
                     random.choice(list(GROUP_HINTS))))
    while len(rows) < n:
        rows.append((random.choice(AREAS), random.choice(TIMES),
                     random.choice(BUDGETS), _pick(INTERESTS, random.randint(1, 3)),
                     _pick(PREFERENCES, random.randint(1, 2)),
                     random.choice(list(GROUP_HINTS))))

    pairs = []
    for area, minutes, budget, interests, prefs, group in rows:
        register = random.random()
        if register < 0.45:
            text = example_en(area, minutes, budget, interests, prefs, group)
        elif register < 0.8:
            text = example_hi(area, minutes, budget, interests, prefs, group)
        else:
            text = example_mixed(area, minutes, budget, interests, prefs, group)
        pairs.append({"input": text, "output": _json_a(area, minutes, budget, interests, prefs)})

    # Partial / missing-field cases so the model learns to omit gracefully.
    partials = [
        ("I want something local and quiet in Bandra",
         {"location": "Bandra", "interests": ["local life"], "preferences": ["local", "quiet"]}),
        ("Kuch accha khaane ka jagah Colaba mein",
         {"location": "Colaba", "interests": ["food"]}),
        ("2 hours free, surprise me with art",
         {"time_minutes": 120, "interests": ["art"]}),
        ("Budget ₹500, vegetarian only",
         {"budget_inr": 500, "preferences": ["vegetarian", "budget"]}),
        ("Kuch hidden gems batao",
         {"preferences": ["hidden"]}),
        ("Rooftop dinner near Marine Lines",
         {"location": "Marine Lines", "interests": ["food"], "preferences": ["rooftop"]}),
        ("Family ke saath 3 ghante, indoor chahiye",
         {"time_minutes": 180, "preferences": ["indoor", "family-friendly"]}),
        ("Cheap street food walk in Dadar",
         {"location": "Dadar", "interests": ["food", "local life"],
          "preferences": ["budget", "outdoor"]}),
    ]
    for text, out in partials:
        pairs.append({"input": text, "output": out})

    random.shuffle(pairs)
    split = int(len(pairs) * 0.85)
    return pairs[:split], pairs[split:]


# ---------------------------------------------------------------------------
# Task B — explanation generation
# ---------------------------------------------------------------------------

EXPERIENCES = [
    ("Cafe Zoe", "cafe", 350, 90, True, ["local", "quiet", "food"]),
    ("Britannia & Co", "restaurant", 700, 75, True, ["heritage", "food", "iranian"]),
    ("Marine Drive Promenade", "walk", 0, 60, False, ["waterfront", "sunset", "free"]),
    ("Chor Bazaar Antique Hunt", "market", 0, 120, False, ["shopping", "heritage", "hidden"]),
    ("Jehangir Art Gallery", "gallery", 100, 75, True, ["art", "culture", "indoor"]),
    ("Bandra Chapel Road Street Art", "walk", 0, 45, False, ["art", "local", "hidden"]),
    ("Dadar Flower Market", "market", 0, 60, False, ["local life", "morning", "budget"]),
    ("Prithvi Theatre", "theatre", 400, 120, True, ["culture", "art", "evening"]),
    ("Carter Road Sunset Promenade", "walk", 0, 45, False, ["waterfront", "sunset", "free"]),
    ("Kala Ghoda Cafe", "cafe", 500, 60, True, ["art", "quiet", "food"]),
    ("Global Vipassana Pagoda", "meditation", 0, 120, True, ["wellness", "quiet", "free"]),
    ("Sanjay Gandhi National Park", "nature", 85, 240, False, ["nature", "adventure", "outdoor"]),
    ("Haji Ali Dargah", "heritage", 0, 60, False, ["heritage", "culture", "free"]),
    ("Colaba Causeway Bazaar", "market", 0, 90, False, ["shopping", "budget", "popular"]),
    ("Versova Fishing Village", "walk", 0, 60, False, ["local life", "morning", "hidden"]),
    ("Oshiwara Night Market", "market", 250, 90, False, ["food", "nightlife", "late-night"]),
]

WEATHERS = ["clear", "cloudy", "rain", "storm", "hot"]

STYLE_POSITIVE = [
    "fits your {t}-minute window",
    "costs about ₹{c}",
    "is {io} (good for today's {w})",
    "matches your taste for {tag}",
    "is only a short ride from where you are",
]

TAGS_BY_PREF = {
    "indoor": "indoor",
    "local": "local spots",
    "quiet": "quiet places",
    "budget": "low-cost options",
    "waterfront": "waterfront views",
    "sunset": "sunset timing",
    "hidden": "hidden gems",
    "art": "art",
    "food": "food",
}


def _weather_note(indoor, weather):
    """Weather copy must depend on indoor/outdoor, not just the condition."""
    if weather == "rain":
        return "good for today's rain" if indoor else "a likely washout in this rain"
    if weather == "storm":
        return "a sensible pick for the storm" if indoor else "risky during a storm"
    if weather == "hot":
        return "shaded from the midday heat" if indoor else "better early or after sunset to dodge the heat"
    if weather == "clear":
        return "great in clear weather"
    return "comfortable for the current cloud cover"


def build_explanation(exp, constraints, weather):
    name, kind, cost, dur, indoor, tags = exp
    io = "indoor" if indoor else "outdoor"
    wnote = _weather_note(indoor, weather)

    bits = []
    t = constraints.get("time_minutes")
    if t is not None:
        if dur <= t:
            bits.append(f"fits your {t}-minute window")
        else:
            bits.append(f"runs {dur} minutes, a little over your {t}-minute window")
    b = constraints.get("budget_inr")
    if b is not None:
        if cost == 0:
            bits.append("is free")
        elif cost <= b:
            bits.append(f"costs about ₹{cost}, within your ₹{b} budget")
        else:
            bits.append(f"costs about ₹{cost}, a stretch on your ₹{b} budget")

    prefs = constraints.get("preferences", [])
    matched = [p for p in prefs if p in tags or (p == "indoor" and indoor) or (p == "outdoor" and not indoor)]
    if matched:
        bits.append("matches your " + ", ".join(matched) + " preference")
    bits.append(f"is {io} — {wnote}")

    if not bits:
        return f"{name} is a solid {kind} option whenever you are in the area."
    return f"{name} " + "; ".join(bits[:3]) + "."


def build_task_b(n=260):
    pairs = []
    for _ in range(n):
        exp = random.choice(EXPERIENCES)
        constraints = {
            "time_minutes": random.choice(TIMES),
            "budget_inr": random.choice(BUDGETS),
            "interests": _pick(INTERESTS, random.randint(1, 2)),
            "preferences": _pick(PREFERENCES, random.randint(1, 2)),
        }
        # Occasionally drop a field to mirror partial inputs.
        if random.random() < 0.15:
            constraints.pop(random.choice(["time_minutes", "budget_inr"]))
        weather = random.choice(WEATHERS)
        inp = {
            "experience": {
                "name": exp[0], "category": exp[1], "cost_inr": exp[2],
                "duration_minutes": exp[3], "indoor": exp[4], "tags": exp[5],
            },
            "constraints": constraints,
            "context": {"weather": weather},
        }
        pairs.append({"input": inp, "output": build_explanation(exp, constraints, weather)})

    random.shuffle(pairs)
    split = int(len(pairs) * 0.85)
    return pairs[:split], pairs[split:]


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

TASK_A_HEADER = """You are LocalIQ's constraint extractor for Mumbai local discovery.
Given a traveller's free-text request (English, Hindi, or code-mixed Hinglish),
return ONLY a JSON object with these keys:
  location (string or omitted), time_minutes (integer or omitted),
  budget_inr (integer or omitted), interests (array of strings),
  preferences (array of strings).
Omit any field the user did not state. Never invent a location or budget.
Use these interest values: food, culture, history, art, nature, heritage,
nightlife, shopping, wellness, adventure, local life."""

TASK_B_HEADER = """You are LocalIQ's explanation writer. Given one experience,
the traveller's constraints, and the weather context, write 2-4 concise lines
in LocalIQ's house style. Always reference time fit, cost fit, and how the
experience matches a stated preference or the weather. Be honest about
trade-offs when the budget or time is tight. No filler, no emoji."""


def render_a(pairs):
    out = [TASK_A_HEADER, ""]
    for p in pairs:
        out.append("### Input")
        out.append(p["input"])
        out.append("### Output")
        out.append(json.dumps(p["output"], ensure_ascii=False))
        out.append("")
    return "\n".join(out)


def render_b(pairs):
    out = [TASK_B_HEADER, ""]
    for p in pairs:
        out.append("### Input")
        out.append(json.dumps(p["input"], ensure_ascii=False))
        out.append("### Output")
        out.append(p["output"])
        out.append("")
    return "\n".join(out)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    a_train, a_eval = build_task_a()
    b_train, b_eval = build_task_b()

    (OUT / "constraint_extraction.txt").write_text(render_a(a_train), encoding="utf-8")
    (OUT / "explanation_generation.txt").write_text(render_b(b_train), encoding="utf-8")

    for name, rows in (("constraint_extraction", a_eval), ("explanation_generation", b_eval)):
        with (OUT / f"{name}.eval.jsonl").open("w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"constraint_extraction: {len(a_train)} train / {len(a_eval)} eval")
    print(f"explanation_generation: {len(b_train)} train / {len(b_eval)} eval")
    print(f"written to {OUT}")


if __name__ == "__main__":
    main()
