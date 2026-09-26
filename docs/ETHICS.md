# Ethics

LocalIQ recommends real places to real people. That carries responsibilities
beyond making the demo work. This document is our stance.

## 1. Honest recommendations

- No paid placement. Ranking is based on the traveller's constraints, not on who
  paid us.
- No fabricated ratings, reviews, or availability.
- Feasibility is computed, not guessed: if we say something fits your 2-hour
  window, it actually does.

## 2. Transparency, not black boxes

- Every recommendation explains *why* it was chosen.
- The ranking model is a rule-based weighted sum, deliberately chosen because it
  is auditable. We do not hide behind an opaque score.
- The AI guide is labelled as AI, and its prompt forbids inventing prices, hours,
  or menu items.

## 3. Data and privacy

- The dataset is curated. We do not scrape personal data.
- We do not build shadow profiles of users.
- API keys and tunnel URLs are treated as secrets.
- Any future accounts will follow data minimisation: collect only what the
  feature needs.

## 4. Fairness to local businesses

- We do not fabricate reviews or inflate ratings for anyone.
- Small, independent places are not disadvantaged by popularity bias; the
  "local gem" signal is surfaced deliberately.
- Booking or payments (future) must be transparent about fees.

## 5. Accessibility

- Accessibility is a hard constraint, not a cosmetic filter. If a user needs
  wheelchair access or low-walking options, infeasible places are excluded.

## 6. AI limitations

- Local LLMs are smaller and less reliable than hosted frontier models.
- The model can still be wrong. Outputs are guidance, not fact.
- The system is designed to fail safe: heuristic parsing and canned replies keep
  the experience correct when the model is unavailable or slow.

## 7. Environmental note

- Running a small local model (3B) rather than a large hosted one reduces network
  and data-centre cost for this use case.

## 8. Scope honesty

- This is a hackathon prototype. It is a frontend + local backend simulation for
  Mumbai, with a clearly labelled production roadmap. We do not claim live
  bookings, real guides, or nationwide coverage that does not exist.
