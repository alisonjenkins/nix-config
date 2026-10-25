---
id: "0004"
host: ali-desktop
date: 2026-10-25T11:40:00Z
finding: 2026-10-25-ali-desktop#4
decision: configure
reason: "Read averaged 6.4 KB per call and was 39% of tool-result tokens; the shared mandate now asks for ranged reads after Grep"
metric: { question: tool-result-size, key: Read, baseline: 1811356, unit: tokens/week }
acted_on: "nix-config#764"            # commit sha or ADR once done
outcome: null             # effective | ineffective | inconclusive (set by a later review)
outcome_review: null
---
Whole-file Reads were the largest share of tool-result tokens. The shared mandate now asks for a ranged Read (offset and limit) once a search has found the lines.
