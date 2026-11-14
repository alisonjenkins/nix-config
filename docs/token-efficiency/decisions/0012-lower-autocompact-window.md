---
id: "0012"
host: Alisons-MacBook-Pro
date: 2026-11-11T00:00:00Z
finding: 2026-11-11-Alisons-MacBook-Pro#1
decision: configure
reason: "three separate reviews in a row (2026-11-02, -03, -11) each found a costly session sitting in the 240k-300k token band, under the autoCompactWindow=350000 trigger set by decision 0002, so it never compacted and drove 30-70% of weekly spend each time"
metric: { question: costly-sessions, key: "6ae60262-687b-4895-a8cb-281469593658", baseline: 30.4047, unit: usd/week }
acted_on: "b42e0cf6"
outcome: null
outcome_review: null
---
Decision 0002 set `autoCompactWindow = 350000`, verified effective for the 680k-939k
token sessions it targeted (140.971 -> 1.1146 usd/week). Decision 0007 flagged a second,
lower cost band -- sessions growing to 264k-300k tokens -- that the 350k trigger misses
entirely, and left the choice open between lowering the threshold and a delegation-based
fix. Three consecutive weekly reviews (2026-11-02, -03, -11) have each surfaced a costly
session in that 240k-300k band, so the gap is recurring rather than one-off.

This decision lowers `autoCompactWindow` from 350000 to 200000
(`home/programs/claude-code/default.nix:425`) to bring that band under the compaction
trigger. The delegation-based alternative from 0007 (splitting/delegating sub-steps
earlier in a long session) is not mutually exclusive and remains worth pursuing
separately for sessions whose cost comes from turn count and cache-healthy volume
rather than re-read waste, where a lower compaction window alone would not help.
