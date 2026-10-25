---
id: "0001"
host: ali-desktop
date: 2026-10-25T11:40:00Z
finding: 2026-10-25-ali-desktop#2
decision: configure
reason: "general-purpose sub-agents spawned without a model ran on Sonnet; CLAUDE_CODE_SUBAGENT_MODEL=haiku catches exactly those since 2.1.251"
metric: { question: delegation-tier-fit, key: general-purpose@claude-sonnet-5-5, baseline: 49.83, unit: usd/week }
acted_on: "nix-config#763"            # commit sha or ADR once done
outcome: null             # effective | ineffective | inconclusive (set by a later review)
outcome_review: null
---
Sub-agents spawned without a model were running on Sonnet, which cost about $49.8 a week. Setting CLAUDE_CODE_SUBAGENT_MODEL=haiku moves those default runs to Haiku; calls that set a model keep it.
