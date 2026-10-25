---
id: "0005"
host: ali-desktop
date: 2026-10-25T11:40:00Z
finding: 2026-10-25-ali-desktop#5
decision: dismiss
reason: "best candidate saves $1.8/week and the repeats data carries 7077 duplicate records; revisit after the ledger dedupe"
metric: { question: script-candidates, key: shape:bash, baseline: 1.83, unit: usd/week }
acted_on: null            # commit sha or ADR once done
outcome: null             # effective | ineffective | inconclusive (set by a later review)
outcome_review: null
---
The best script candidate would save about $1.8 a week, which is below the floor for building a tool. The repeats data also carries 7077 duplicate records, so the ranking is revisited after the ledger dedupe.
