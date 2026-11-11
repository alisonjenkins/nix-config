---
id: "0015"
host: Alisons-MacBook-Pro
date: 2026-11-11T09:30:20Z
finding: 2026-11-11-Alisons-MacBook-Pro#4
decision: dismiss
reason: "fork@claude-sonnet-5 dominates subagent-overhead (75.5%) and delegation-tier-fit ($10.02/wk) spend, but forks always inherit the parent session's model by design and cannot be routed to a cheaper tier, so this isn't the kind of misrouted delegation decision 0001 targeted"
metric: { question: delegation-tier-fit, key: fork@claude-sonnet-5, baseline: 10.0218, unit: usd/week }
acted_on: null
outcome: null
outcome_review: null
---
fork@claude-sonnet-5 is 91.5% of delegation-tier-fit spend and 75.5% of subagent-overhead
tokens this window. At first glance this looks like the same misrouted-tier problem
decision 0001 fixed (CLAUDE_CODE_SUBAGENT_MODEL=haiku), but forks are architecturally
different: a fork always runs on the parent session's model (a model override is ignored
for them) because they inherit the parent's full context and cache. Decision 0001's
mandate routes spawned fresh sub-agents (general-purpose, Explore) to the cheapest tier
that fits, which this digest shows working as intended (Explore@claude-sonnet-5 is only
$0.88/week). No action here. Noted so this line isn't mistaken for a regression of 0001
in a future review.
