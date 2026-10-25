---
id: "0002"
host: ali-desktop
date: 2026-10-25T11:40:00Z
finding: 2026-10-25-ali-desktop#1
decision: configure
reason: "sessions grew to 680k–939k tokens of context and every later request re-read it; autoCompactWindow 350000"
metric: { question: agent-context-growth, key: 6b62c72e-f27d-4223-8cca-1622ad91e04f, baseline: 938700, unit: tokens }
acted_on: "nix-config#763"            # commit sha or ADR once done
outcome: null             # effective | ineffective | inconclusive (set by a later review)
outcome_review: null
---
Some sessions grew to between 680k and 939k tokens of context, and each later request re-read all of it. Setting autoCompactWindow to 350000 compacts them earlier, so the re-read stays smaller.
