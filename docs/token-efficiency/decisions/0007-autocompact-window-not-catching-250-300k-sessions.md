---
id: "0007"
host: Alisons-MacBook-Pro
date: 2026-11-11T09:30:20Z
finding: 2026-11-03-Alisons-MacBook-Pro#3
decision: configure
reason: "three separate sessions this review period (cc8a7f62, 339d3f47, 86b48fab) grew to 264k-300k tokens of context and drove 62-70% of weekly spend, all under the autoCompactWindow=350000 set by decision 0002; the threshold isn't catching this cost band"
metric: { question: costly-sessions, key: cc8a7f62-87e7-4d2c-9bac-0ade06514096, baseline: 10.62, unit: usd/week }
acted_on: null
outcome: null
outcome_review: null
---
Decision 0002 set `autoCompactWindow = 350000` to compact sessions that had grown to
680k-939k tokens. Across the 2026-11-02 and 2026-11-03 reviews, three different sessions
(cc8a7f62-87e7-4d2c-9bac-0ade06514096: $10.16-$10.62/week, context 35k->300k over 10
turns; 339d3f47-d280-4857-9109-7b4e778c0ee3: $7.39/week, context to 274,714, compacted
once; 86b48fab-1873-4f5e-b598-dfc6168427f0: $15.19/week, context 94,589->279,445+ over
31 turns, cache hit healthy throughout) sat in the 264k-300k band -- real cost, but
under the 350k compaction trigger, so only one of the three ever compacted. Two options
worth weighing, not decided here: lower `autoCompactWindow` (e.g. to ~200000) so this
band compacts too, or treat it as a delegation problem instead (split/delegate sub-steps
earlier in a long session) since 86b48fab's cache hit was fine throughout -- the cost
there was turn count and volume, not re-read waste, so a lower compaction window would
not have helped that one.
