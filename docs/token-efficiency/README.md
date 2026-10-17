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

## Not yet answerable

Questions worth asking that the collected signals cannot answer yet, and what each needs.
`top.rs` is the `cc-obs-query` ranking code; "ledger" is `cc-obs-ledger`.

| Question | Needs |
|---|---|
| Skills installed but never activated, and what the listing costs | Ledger: gauge `cc_obs_ledger_skill_listed_tokens{skill_name}` per installed skill at SessionStart (the census only emits the `skills_listing` total). `top skill --unactivated` is built and `skills-loaded-unused` asks it; both report unavailable until the gauge exists |
| MCP servers connected but never called | Ledger: gauge `cc_obs_ledger_mcp_server_connected{mcp_server_name}` at SessionStart. `top mcp --idle` is built and reports the gap until the gauge exists; then point `mcp-idle-servers` at it |
| Cache-write churn: prefix invalidated after the first turns, or idle gaps beyond the cache TTL | Ledger: `cc_obs_ledger_cache_creation_tokens{session.id,turn}` and the seconds since the previous request per turn |
| Tokens added per prompt by hooks, against a budget | Recall is answered by `top memory --by tokens-per-request`; hook output needs `claude_code.hook_execution.additional_context_chars` read by a query (it is in `retire:` now) |
| Large Bash results by command shape (`sed -n` ranges, grep, cat) | Ledger: a `command_shape` attribute (first word and flag class only, never arguments) on `cc_obs_ledger.tool_call` records, and `top.rs`: `top tool --by shape` |
| Tokens spent before each compaction and turns it bought | `top.rs`: per-compaction rows joining `compaction` pre/post tokens to the `turn` of `cc_obs_ledger_context_tokens`; today only a count per session |

## script-candidates

`cc-obs-query automate [--since 7d] [--min-count 3]` (bounded like the other commands: `--limit`,
`--offset`, `--format`, `--max-bytes`) ranks repeated Bash work a script or tool could replace.
It reads `cc_obs_ledger.tool_call` records only (shape labels, hashes and sizes, never arguments).
Candidates: a repeated Bash `command_shape`; a sequence of 2 to 4 consecutive Bash calls by one
agent (non-overlapping, shared with `repeats`; a sequence entirely inside a longer listed one is
dropped); a large result followed by a narrower query to the same tool. A sub-agent is its own run,
keyed by `agent_id`.

Score (the report's `score_means`): per candidate, `direct_tokens` = sum over its calls of
`result_bytes / 4 + CALL_TOKENS` (100, an assumption: the records carry no input size);
`carried_token_turns` = sum over its calls of result tokens x calls remaining in that agent's run;
`est_usd` = `direct_tokens` x $2/M + `carried_token_turns` x $0.20/M (Sonnet 5.5 input price from
`home/skills/delegation/tiers.md`; cache-read taken as 10% of it, an assumption). The row `value`
(and the rank) is `est_usd` x `saveable_share`, an assumed fraction a script removes: 0.8 for a
repeated shape, 0.6 for a sequence, 0.5 for large-then-narrow. Row fields: `key`, `pattern`,
`calls` (occurrences), `sessions`, `main` / `sub` occurrences, `est_usd`, `value`, `action`
(`script` at `--min-count` occurrences, `tool` for large-then-narrow, `dismiss` below the floor or
for the catch-all `other` shape), `label` (the readable shapes; `key` is a slug of them).

Without `command_shape` on the records (ledger older than the attribute) Bash calls fall back to
`Bash@<input_prefix_hash>` groups and a gap note says command identity needs the new ledger.

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
