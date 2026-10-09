# Token efficiency reviews

Where the weekly review's output and the owner's decisions live. Design:
`specs/007-local-observability-stack/` (formats in `contracts/review-formats.md`).

| Path | What |
|---|---|
| `questions.yaml` | The versioned review-question pack |
| `reviews/` | Findings promoted from a host's review state directory |
| `decisions/` | One decision record per finding: `build`, `configure` or `dismiss`, with the measured outcome added by a later review |

Rules: aggregates and references only, never prompt or file content. The system never
commits; the owner promotes findings and records decisions. Timestamps are ISO 8601 UTC.

## Findings file

The review runner writes a findings file to the host's review state directory; the owner promotes it into `docs/token-efficiency/reviews/`.

```markdown
---
review: 2026-10-09-ali-desktop
host: ali-desktop
period: 2026-10-02/2026-10-09
pack_version: 1
own_cost_usd: 0.31
---
## 1. <title> — est. saving 12k tokens/week (4%)
Evidence: <refs, no content>. Suggested action: build-tool | configure. Status: proposed
```

- Ranked by estimated saving, at most 5 per review
- Dismissed items carry the earlier reason
- Aggregates and references only, never prompt or file content

## Decision record

The decision record lives at `docs/token-efficiency/decisions/NNNN-<slug>.md` and is written and committed by the owner.

```markdown
---
id: "0007"
host: ali-desktop
date: 2026-10-09T00:00:00Z
finding: 2026-10-09-ali-desktop#1
decision: build | configure | dismiss
reason: <one line>
metric: { question: tool-result-size, key: Read, baseline: 41200, unit: tokens/week }
acted_on: null            # commit sha or ADR once done
outcome: null             # effective | ineffective | inconclusive (set by a later review)
outcome_review: null
---
```

- Aggregates and references only, never prompt or file content (safe in the repo)
- Timestamps ISO 8601 UTC
- The system proposes edits to `outcome` in the next findings file, the owner commits them (the system never commits)
