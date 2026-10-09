# Contract: `cc-obs-query` CLI and digest

Read-only. Output is bounded by design: every command defaults to `--format concise`,
`--limit 10`, and a hard byte cap (`--max-bytes`, default 8192) that truncates with a
trailing `truncated: true, next: "<flag to continue>"` marker. All output is JSON unless
`--format table`. Errors are one JSON object on stderr `{error, operation, input, fix}` and
exit non-zero, so the model can self-correct.

Data labelled `review.run=1` (the unattended review's own `claude -p` runs) is excluded from
every ranking by default, so the review does not analyse itself; `--include-review` includes
it, and the excluded spend is reported as the review's own cost.

Endpoints come from the stack options (read from `$XDG_CONFIG_HOME/cc-obs/endpoints.json`, which the module writes; env `CC_OBS_ENDPOINTS` overrides), never
hard-coded.

| Command | Purpose | Key flags |
|---|---|---|
| `cc-obs-query top <category>` | Rank token consumers. Categories: `tool`, `skill`, `mcp`, `subagent`, `memory`, `fixed`, `model`, `project`, `session` | `--since 7d`, `--by cost\|tokens` (tokens exclude cache read and creation), `--by cache-hit` and `--by compactions` (session only), `--by hit-rate` (memory only), `--limit`, `--offset`, `--max-bytes`, `--format` |
| `cc-obs-query tool <name>` | Calls, mean and max result size, share of tokens, repeat rate | `--since` |
| `cc-obs-query session <id>` | Context per turn, cache hit ratio, fixed vs new tokens | `--detail` adds per-turn rows |
| `cc-obs-query repeats` | Near-identical calls within a session; large result then narrowing query; frequent call sequences | `--since`, `--min-count` |
| `cc-obs-query recall` | Injected tokens per prompt, matches used vs ignored, failures | `--since` |
| `cc-obs-query compare <question-id> --a <range> --b <range>` | Same figure across two ranges (FR-025) | ranges like `2026-09-01..2026-09-08` |
| `cc-obs-query unused-signals` | Collected signals no question in the pack references (FR-036) | `--pack` |
| `cc-obs-query digest --write <file>` | Validates a digest submitted by the stage 1 model (schema, `--max-bytes 32768`, no content-like fields, every cited evidence reference exists) and saves it | `--pack`, `--since`, `--out` |
| `cc-obs-query digest --baseline` | Runs the whole question pack mechanically with no model; the fallback when stage 1 fails | `--pack`, `--since`, `--out` |
| `cc-obs-query health` | Store reachability and guard state | |

Figures with no data return `{"value": null, "unavailable": "<why>"}`, never `0`.

## Digest JSON

```json
{
  "schema": 1,
  "stage1": "model",
  "host": "ali-desktop",
  "period": {"start": "2026-10-02T00:00:00Z", "end": "2026-10-09T00:00:00Z"},
  "pack": {"version": 1, "sha": "<git blob sha>"},
  "stack": {"stores_ok": true, "guard": "ok", "gaps": ["fixed-context unavailable before 2026-10-04"]},
  "totals": {"tokens": 0, "est_cost_usd": 0.0, "sessions": 0},
  "questions": [
    {"id": "tool-result-size", "title": "...", "rows": [{"key": "Read", "value": 0, "share": 0.0, "evidence": "<short ref>"}], "truncated": false}
  ],
  "prior_decisions": [{"id": "0007", "status": "acted", "before": 0, "after": 0, "verdict": "effective"}],
  "own_cost": {"tokens": 0, "est_cost_usd": 0.0}
}
```

`stage1` is `"model"` when the low-cost model gathered it and `"baseline"` when the
mechanical fallback did. The stage 1 model is limited to the commands in this contract and a
bounded number of drill-downs per question (default 3).

Rules: no prompt text or file contents; evidence is a reference (session id, tool name,
timestamp), not content. Total digest size ≤ `--max-bytes` (default 32 KiB).

## Query core

One library crate holds the queries; `cc-obs-query` is a thin CLI over it. For experiment S4 the same
core is wrapped once as an MCP stdio server (throwaway adapter). The loser is deleted.
