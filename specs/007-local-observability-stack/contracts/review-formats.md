# Contract: review question pack, findings, decision records

## Question pack: `docs/token-efficiency/questions.yaml`

```yaml
version: 1
regrowth_factor: 1.5        # dismissed findings re-surface above this growth
questions:
  - id: tool-result-size
    title: Which tools return the most tokens per use?
    signals: [claude_code.tool_result.tool_result_size_bytes, claude_code.token.usage]
    query: { command: "cc-obs-query top tool --by tokens" }
    decision_kind: build-tool | configure | dismiss
    threshold: { min_share: 0.03, min_calls: 20 }
```

Rules: every `signals` entry is a real collected signal; `cc-obs-query unused-signals` fails the
check if a collected signal is in no question, unless listed under `retire:` (FR-036). The pack
is part of the repository, so the digest records its blob sha.

Starting questions: tool-result-size, repeat-calls, skills-loaded-unused,
mcp-idle-servers (servers connected but never called in the period), fixed-context-share, cache-hit-low-sessions, subagent-overhead,
memory-injected-ignored, compaction-frequency, recall-failures.

## Findings file (draft in state dir; promoted into `docs/token-efficiency/reviews/`)

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

Ranked by estimated saving, at most 5 per review. Dismissed items carry the earlier reason.

## Decision record: `docs/token-efficiency/decisions/NNNN-<slug>.md`

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

Rules: aggregates and references only, never prompt or file content (safe in the repo);
timestamps ISO 8601 UTC; the system proposes edits to `outcome` in the next findings
file, the owner commits them (the system never commits).
