# Data Model: Local Observability Stack

Entities from the spec, with the concrete signal or file each lives in. Names marked
*unconfirmed* depend on spike S3.

## Telemetry sources

| Source | Signal | Where it lands |
|---|---|---|
| Claude Code built-in export | metrics, events (logs), traces (beta) | collector → Prometheus / Loki / Tempo |
| `memory-recall` / `skill-recall` hook | log line per run (existing), span per run (existing), **new** metrics and `session.id` | Loki direct; collector → Tempo, Prometheus |
| `cc-obs-ledger` | metrics and one log line per session | collector |
| Stack self-metrics | scrape of each store, collector and the disk guard | Prometheus |

## Token Account

One per model call. Built from the `api_request` event plus `claude_code.token.usage`.

| Field | Source | Notes |
|---|---|---|
| `session.id`, `host` | resource / standard attributes | `host` added by the collector |
| `repository` (project) | `token.usage` attribute with `OTEL_METRICS_INCLUDE_REPOSITORY`; ledger fallback: working-directory basename | needed for per-project breakdown |
| `model`, `query_source` | `token.usage` attributes | `query_source`: main, subagent, auxiliary |
| `agent.name`, `skill.name`, `mcp_server.name`, `mcp_tool.name` | `token.usage` attributes | empty when not applicable |
| `input`, `output`, `cacheRead`, `cacheCreation` | `token.usage` `type` | tokens |
| `cost_usd` (estimate) | `cost.usage` | labelled as an estimate; list-price table is an option |

Category attribution (spec FR-021): `tool` (from `tool_result_size_bytes` and span
`result_tokens`), `skill` (`skill_activated`), `mcp` (`mcp_server.name`), `memory`
(`additional_context_chars` of the recall hook, and recall log tokens added), `fixed`
(from `cc-obs-ledger`), `subagent` (`query_source=subagent`). Where a figure is missing the
view shows "unavailable", never zero.

## cc-obs-ledger output

| Metric / log | Labels | Meaning |
|---|---|---|
| `cc_obs_ledger_fixed_context_tokens` | `session.id`, `component` (system, instructions, skills_listing, mcp_tools, other) | first-request fixed context, split by the SessionStart census |
| `cc_obs_ledger_context_tokens` | `session.id`, `turn` bucket | context size at each request |
| `cc_obs_ledger_cache_hit_ratio` | `session.id` | cacheRead / (cacheRead + cacheCreation + input), per turn |
| log `cc_obs_ledger.session` | `session.id`, totals | one line at SessionEnd |
| log `cc_obs_ledger.tool_call` | `session.id`, `turn`, `seq`, `tool_name`, `agent_type`, `input_hash`, `input_prefix_hash`, `input_bytes`, `result_bytes` | one per tool call; keyed hashes only, no input content; basis for repeat detection |

## Recall Record

Existing log line (scores, counts, timings, never the prompt) plus:

| Addition | Why |
|---|---|
| `session.id` field and span attribute | join to the Claude Code trace (FR-009) |
| `outcome` = `success` / `empty` / `error` with `cause` | visible failures (FR-008) |
| metrics `recall_requests_total{service,outcome}`, `recall_hits_total`, `recall_latency_seconds`, `recall_tokens_injected_total` | rate, hit rate, latency, cost of recall (FR-010) |

## Review artefacts

| Entity | Form | Location | Lifecycle |
|---|---|---|---|
| Review Question | entry in a YAML pack, versioned | `docs/token-efficiency/questions.yaml` | edited by owner; pack version recorded in each review |
| Digest | JSON, size-bounded | state dir `token-review/<host>/<period>.digest.json` | written by stage 1; expires with raw data |
| Review (findings) | Markdown with front matter | state dir, promoted to `docs/token-efficiency/reviews/` | draft → promoted by owner |
| Optimisation Candidate | one finding inside a review | same file | open → decided |
| Decision Record | Markdown with front matter | `docs/token-efficiency/decisions/` | `build` / `configure` / `dismiss` → measured outcome `effective` / `ineffective` / `inconclusive` |

State transitions of a finding: `proposed` → `decided(build|configure|dismiss)` → (if acted on)
`measured(effective|ineffective|inconclusive)`; a dismissed finding re-surfaces only when its
metric has grown by the pack's `regrowth_factor` (default 1.5×).

Formats: [contracts/review-formats.md](contracts/review-formats.md).

## Retention Policy

30 days (option) for each store; total disk budget 20 GB (option), reported when exceeded,
never stops ingestion. Guard state (`guard.json`): `ok` / `over`; transitions at 100% and 90%
of the budget.
