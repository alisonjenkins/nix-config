---
id: "0021"
host: ali-desktop
date: 2026-11-12T05:55:00Z
finding: 2026-11-12-ali-desktop#4
decision: configure
reason: "general-purpose sub-agents on Sonnet cost $111.6/week (83% of sub-agent spend), up from the $49.8 baseline of decision 0001; route mechanical steps to the Gemini rung or haiku-worker"
metric: { question: delegation-tier-fit, key: general-purpose@claude-sonnet-5-5, baseline: 111.6368, unit: usd/week }
acted_on: "13edc1a6"
outcome: null
outcome_review: null
---
Decision 0001 set the default sub-agent model to Haiku, yet Sonnet general-purpose spend
more than doubled, so most of it likely comes from Agent calls that set `model: sonnet`
explicitly. The delegation skill's tier test is the lever: make the Sonnet rung require a
step whose design is still open, and send searches, sweeps and specified edits to the
Gemini rung or haiku-worker. The next review checks delegation-tier-fit for the same key.
