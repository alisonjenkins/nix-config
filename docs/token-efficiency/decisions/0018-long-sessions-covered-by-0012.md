---
id: "0018"
host: ali-desktop
date: 2026-11-12T05:55:00Z
finding: 2026-11-12-ali-desktop#1
decision: dismiss
reason: "Already covered by decision 0012 (autoCompactWindow 200000), which landed 2026-11-11T12:02Z, under a day before this window closed; re-measure next review instead of adding a second lever"
metric: { question: costly-sessions, key: 554fed0b-d6f3-5393-a783-582cc1ef366c, baseline: 137.2202, unit: usd/week }
acted_on: null
outcome: null
outcome_review: null
---
The two costliest sessions spent $251 (22% of the week) over 782 and 951 requests with
per-turn contexts of 180k–310k tokens and a 99% cache hit, so the cost is cache reads of a
large context, not new work. That is the 240k–300k band decision 0012 targets, and its
lower compaction trigger was live for less than a day of this window. Adding another lever
now would make 0012's outcome unmeasurable. If the next review still shows sessions above
200k context at this spend, the remaining levers are ending a project thread once its task
is done and sub-agents that return summaries rather than raw output.
