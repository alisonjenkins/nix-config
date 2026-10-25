---
id: "0002"
host: ali-desktop
date: 2026-10-25T11:40:00Z
finding: 2026-10-25-ali-desktop#1
decision: configure
reason: "sessions grew to 680k–939k tokens of context and every later request re-read it; autoCompactWindow 350000"
metric: { question: model-spend, key: claude-sonnet-5-5, baseline: 140.971, unit: usd/week }
acted_on: "nix-config#763"            # commit sha or ADR once done
outcome: null             # effective | ineffective | inconclusive (set by a later review)
outcome_review: null
---
Some sessions grew to between 680k and 939k tokens of context, and each later request re-read all of it. Setting autoCompactWindow to 350000 compacts them earlier, so the re-read stays smaller.

The metric moved from `agent-context-growth` to `model-spend` because its rows are keyed by session id, which never recurs in a later period, and model names do recur; the outcome is the spend on the model that carried most of the window's cost, which is a proxy for re-read cost and includes sub-agent spend.
