# Research: Local Observability Stack

**Date**: 2026-10-09 · **Spec**: [spec.md](spec.md)

Sources are sub-agent desk research (web) and a read-only repo survey, then spot-checked by
the main loop where noted. Items marked *unconfirmed* were not verified against a primary
source and are verified by a spike task before they are relied on.

## R1. Container runtime and runner

**Decision**: One Nix-rendered pod definition (Kubernetes-style YAML) run with
`podman kube play`, on every OS. The runner differs: a systemd user service on Linux (NixOS
and non-NixOS), a launchd agent on macOS that first ensures `podman machine` is up.

**Rationale**:
- A single source of truth for images, ports, mounts and config (constitution V). Home
  Manager's `services.podman.containers` is Quadlet/systemd-only and cannot run on macOS, so
  using it would mean a second definition for macOS.
- All containers share one network namespace in a pod: they reach each other on `localhost`,
  and only the ports we publish leave it. That removes the `host.containers.internal` versus
  `host.docker.internal` problem and makes "bind to 127.0.0.1 only" one place to get right.
- Podman is already opt-in on Linux (`modules/podman`); macOS has no container runtime today.

**Alternatives considered**:
- Home Manager `services.podman.containers` (Quadlet): clean on Linux, no macOS. Rejected: two definitions.
- NixOS `virtualisation.oci-containers`: rootful, NixOS only, does not cover non-NixOS Linux or macOS.
- Docker Desktop / OrbStack / colima / Apple `container`: no declarative module found for any;
  none runs `podman kube play`, so each would need a second pod definition (no single source
  of truth). Not rejected for maintenance cost: the owner already runs Colima + Kind, and the
  stack gets its own dedicated podman machine instead (ADR 0034).
- Native nixpkgs services under systemd/launchd: simplest and avoids the macOS VM, but the
  owner asked for containers. Kept as the fallback if the macOS spike (S1) fails.

**Risks, resolved by spike S1**: `podman kube play` behaviour with a podman machine on macOS
(bind-mount paths, `--replace`, restart on VM reboot), and whether the nix-darwin
`podman` module the search hinted at exists (*unconfirmed*).

## R2. Collector in front of the stores

**Decision**: Include an OpenTelemetry Collector (contrib) in the pod as the single local
OTLP endpoint (4317 gRPC, 4318 HTTP, loopback). Logs go to Loki's OTLP endpoint, traces to
Tempo, metrics to Prometheus. Tempo's own OTLP receiver moves to non-default internal ports so
it does not clash with the collector in the shared namespace.

**Rationale**: Claude Code emits all three signals over OTLP and does not pass `OTEL_*` to
subprocesses, so one endpoint suffices. A collector is also the place to drop sensitive
attributes before they are stored (FR-012) and to attach host labels. `memory-recall`
already pushes to Loki (HTTP push) and Tempo (OTLP/HTTP); it is re-pointed at the collector
for traces and keeps pushing logs to Loki directly.

Prometheus does not turn OTLP resource attributes into labels unless configured, so the
config promotes the ones the views rely on (`host`, `review.run`, `repository`). The exact
key and the Prometheus version that supports it are *unconfirmed*; spike S2 (T006) checks.

**Alternatives**: Claude Code exporting straight to each store (three endpoints, no redaction
point); Prometheus' native OTLP receiver without a collector (no filtering).

## R3. What Claude Code already emits

(Official docs: code.claude.com/docs/en/monitoring-usage; read to ~100k of 150k chars.)

- **Enable**: `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_{METRICS,LOGS,TRACES}_EXPORTER=otlp`,
  `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_EXPORTER_OTLP_ENDPOINT`. Traces are beta and need
  `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`. Honoured only from user-level or managed settings;
  project `.claude/settings.json` is ignored. This repo already merges user-level settings at
  activation (`home/programs/claude-code/default.nix`, `env` block).
- **Metrics**: `claude_code.token.usage` and `claude_code.cost.usage` with `type`
  (input/output/cacheRead/cacheCreation), `model`, `query_source` (main/subagent/auxiliary),
  and `agent.name`, `skill.name`, `mcp_server.name`, `mcp_tool.name`; plus session count,
  active time, lines of code, edit decisions.
- **Events**: `tool_result` (with `tool_input_size_bytes` and `tool_result_size_bytes`,
  `duration_ms`, `success`), `api_request` (tokens, cost, duration, cache tokens),
  `skill_activated`, `subagent_completed` (`total_tokens`, `total_tool_uses`), `compaction`
  (`pre_tokens`, `post_tokens`), `hook_execution_*` (`additional_context_chars`), `api_error`.
- **Traces (beta)**: `interaction` → `llm_request` / `tool` (`result_tokens`) → subagents
  nested under the Agent tool span.
- **Content gates, all off by default**: prompts, tool parameters (Bash commands, skill and
  MCP names in events), tool content, raw API bodies.
- **Not available**: a per-request split of fixed context (system prompt, CLAUDE.md,
  tool schemas, MCP definitions). *Unconfirmed*: join key between events and spans
  (`prompt.id`), tool-result size in tokens outside traces, `PostToolUse` payload size.
- **Open issues reported (unverified on GitHub)**: `query_source` missing on some events after
  May 2026; sub-agent id absent on tool spans.

Project attribution needs `OTEL_METRICS_INCLUDE_REPOSITORY=1` (default false; docs say
v2.1.269+). The module sets it (option `claudeCode.includeRepository`, default true) and
`cc-obs-ledger` also labels its own metrics with the working-directory basename as a fallback;
whether the built-in attribute is the repository name or a hash is *unconfirmed*, T032 checks.

**Decision**: Use the built-in export for everything it covers. Fill the fixed-context gap
with a small transcript reader (R4). Keep the content gates off (`captureToolDetails`
option, default false); skill and MCP attribution comes from metric attributes, which need
no gate.

## R4. Filling the fixed-context gap

**Decision**: A small Rust command, `cc-obs-ledger`, run from the `Stop` and `SessionEnd` hooks
outside the prompt's critical path (same pattern as `memory-recall ship`: spawned detached,
best effort, 3 s timeouts). It reads the session transcript's per-request `usage` and emits:
first-request fixed-context tokens (input plus cache creation before any user content),
cache-hit ratio per turn, and context size per turn, as OTLP metrics to the collector.
For repeat detection it also reads each tool call's input from the transcript and emits only a
keyed one-way hash (HMAC with a per-host secret kept in the state directory, never in the Nix
store), the input size and the result size; the input itself is never sent (spec FR-024
works under the default privacy gates). It also runs a one-off census at `SessionStart` (token estimate per instructions file,
skills listing, MCP tool definitions) so the fixed total can be split by component.

**Rationale**: Hooks and the transcript are documented sources; no wrapper around Claude Code
is needed (spec assumption). Rust matches `scripts/retrieval-eval` and the constitution's
clippy gate. Transcript field names are *unconfirmed*: spike S3 checks them against a real
transcript before the schema is fixed.

**Alternatives**: parse transcripts in the weekly review only (no live context-per-turn
view; cannot join to metrics); wrap the `claude` binary (fragile, rejected by spec).

## R5. Disk bounds (30 days, 20 GB total)

| Store | Retention | Size bound | Basis |
|---|---|---|---|
| Prometheus | `--storage.tsdb.retention.time=30d` | `--storage.tsdb.retention.size=4GB` | self-enforcing (confirmed) |
| Loki | `retention_period: 720h`, compactor `retention_enabled` | none native | ingest-rate limit plus measured sizing |
| Tempo | `block_retention: 720h` (*key unconfirmed*) | none native | per-trace size limit plus measured sizing |

Loki and Tempo have no size cap. **Decision**: a disk guard, a timer-driven check of the data
directory against `maxDiskGB` (default 20). Over the budget it never stops ingestion: it
writes `guard.json`, pushes `observability.guard.over_budget`/`used_bytes`/`cap_bytes`, and
notifies (session-start notice, desktop notification at most once per 24 h); the state returns
to `ok` when usage falls under 90% (ADR 0035). Budget split is a starting guess
(Prometheus 4, Loki 7, Tempo 7, keeping 10% headroom) and is re-measured after one week of data (disk use is recorded in the evidence for T042 and T072). The budget is reported, not enforced:
losing new telemetry is worse than using more disk.

**Alternatives**: filesystem quotas (btrfs qgroup / xfs project quota): not portable to
macOS or to the other Linux filesystems in use; deleting the oldest Loki/Tempo blocks
ourselves: risks corrupting stores, rejected.

## R6. Images and pinning

Latest tags seen 2026-10-09 (Docker Hub): grafana 12.4.12, loki 3.7.8, tempo 2.10.8,
prometheus v3.13.4, otel-collector-contrib 0.162.0. **Decision**: pin `tag@sha256:digest`;
digests are fetched at implementation time (not guessed). `grafana/otel-lgtm` rejected: demo
image, no per-service retention control. Renovate-style bumps are deliberate edits, covered
by a check that fails on any floating tag or missing digest (FR-003).

## R7. Verification without running containers (FR-019)

**Decision**: Pure flake checks under `flake-modules/` following the existing
`obs-config-tests.nix` pattern (bats in `runCommand`): render the pod YAML and the store
configs, assert pinned digests, loopback-only port bindings, retention values, datasource
provisioning, absence of content-capture settings by default. Plus eval-only assertions that
the Linux and darwin home configurations both contain the stack with the right runner
(systemd user unit versus launchd agent). The runtime itself (podman machine, real ingest)
cannot run in CI and is named untestable glue per constitution II; `quickstart.md` covers it
as a manual check on one host per OS.

## R8. MCP versus CLI for the analysis tools

(Desk research; every benchmark is vendor- or single-author-run, mostly GitHub and Playwright,
none on analytics backends.)

- Idle cost is small for both under Claude Code's default tool deferral; per-call output
  size dominates.
- Scalekit (vendor, n=75, five GitHub tasks): median tokens per run roughly 1.4k to 9k for CLI,
  32k to 83k for an MCP server with 43 tool schemas; CLI completed 25/25 runs against
  MCP's 18/25 (TCP-level timeouts). A later Playwright re-test found MCP within about 1% of
  the CLI once snapshots were written to disk. So the gap comes from schema size and
  unfiltered output, not the protocol.
- Anthropic's own guidance favours concise-by-default responses, filtering before returning,
  pagination and actionable errors in either form; CLI additionally allows piping to cut
  output before it reaches context.
- Repo evidence points the other way for idle cost: the MCP gateway hid downstream tool names
  and cut baseline context; skills cost one description line each.

**Decision**: Hypothesis only: CLI plus skill (moderate confidence). Final choice is made by the
FR-038 experiment (spike S4, run once the query library exists and before the review runner is built), because the workload here (read-only analytics, a few runs a
week, one user) is not the one any benchmark measured. Protocol for S4 is in
`quickstart.md`; the query core is written once and wrapped twice for the experiment.

## R9. Scheduled, two-tier review

**Decision**: A timer (systemd user timer on Linux, launchd `StartCalendarInterval` on macOS)
runs `claude -p` non-interactively, which the repo already does in `llm_run.rs`. Stage 1 uses
a haiku-class model to run the `cc-obs-query` commands for each question in the versioned
pack, follow up on anomalies with a bounded number of drill-downs (for example one session
detail per top offender), choose the evidence references, and submit the digest through
`cc-obs-query digest --write`, which validates schema, size cap and "no content" before saving.
If stage 1 fails or hits its budget, the runner falls back to `cc-obs-query digest --baseline`,
which runs the pack mechanically with no model, and marks the digest `stage1: "baseline"`.
Stage 2 uses a stronger model that reads only the digest and writes the findings. `--max-budget-usd` exists in the installed CLI (checked with
`claude --help`) and caps each stage. Output goes to a per-host state directory, never
straight into the repository: the owner promotes findings into `docs/token-efficiency/`
with their decision (the system never commits). Missed runs are detected by comparing the
last digest's period end to now and catch up on the next run.

**Alternatives**: one strong-model stage over raw queries (more tokens, against the goal);
no-model digest only (rejected by the owner in clarification Q1).

## R10. Facts about this repository that shape the plan

- `memory-recall` already ships a log line to Loki and a span to Tempo per hook run, with
  options `telemetry.{lokiUrl,tempoEndpoint,tenantId,headersFile,labels}`. The spec's
  "needs new instrumentation" reduces to: recall metrics, and carrying the Claude Code
  `session.id` so a recall joins its prompt (FR-009, FR-010).
- Home modules are exported in `flake-modules/home-modules.nix`; `flake-modules/darwin-modules.nix`
  exports darwin modules. The macOS work host is `ali-work-laptop-macos`
  (hostname `Alisons-MacBook-Pro`); `ali-mba` is the other darwin config.
- Ports in use: 8080 (llama), 8110 (memory-recall embedder), 9100 (node exporter). 3000,
  3100, 3200, 4317, 4318, 9090 are free locally. A cluster Loki exists at a LAN address;
  no local clash.
- Last ADR is 0033. Skills in `home/skills/<name>/`. No existing skill named for tokens or cost.

## Spike results

### T009 image digests (2026-10-09)

Read with `skopeo inspect` (the Digest is the manifest-list digest, so it covers amd64 and
arm64); recorded in `home/modules/observability-stack/images.nix`. Cross-checked by hashing
`skopeo inspect --raw` output for loki.

### S3 transcript and hook fields (T007, 2026-10-09)

Read from a real session transcript (structure only, no content):

- One JSONL line per content block. A single API request appears as several `assistant`
  lines with the same `requestId` and `message.id`, differing in `apiBlockIndex`, and the
  **same `message.usage` object is repeated on every line**. Counting usage per line
  over-counts by 1 to 5 times (in the sample: 157 requests with one line, 382 with two, 308
  with three, 134 with four, 53 with five). **Count each `requestId` once.**
- `message.usage` keys: `input_tokens`, `output_tokens`, `cache_read_input_tokens`,
  `cache_creation_input_tokens`, `cache_creation{ephemeral_5m_input_tokens,
  ephemeral_1h_input_tokens}`, `speed`, `service_tier`, `iterations`.
- Assistant line keys include `sessionId`, `requestId`, `cwd`, `gitBranch`, `isSidechain`
  (true for sub-agent turns), `timestamp`, `version`, `effort`.
- Tool calls: `message.content[]` items with `type: "tool_use"` and keys `id`, `name`,
  `input`, `caller`. Results: a `user` line with `message.content[0].type == "tool_result"`
  (keys `tool_use_id`, `content`, `is_error`), `toolUseResult`, `sourceToolAssistantUUID` and
  **`promptId`**, which joins a tool result to its prompt.
- Not confirmed here: hook payload field names (`prompt_id`, `agent_id`) and the event-to-span
  join key in the telemetry export; the transcript's `promptId` is the likely match.

### S5 unattended `claude -p` (T008, 2026-10-09)

- `claude -p --output-format json --max-budget-usd 0.05 --model haiku "<prompt>"` works with
  the owner's existing auth. The result JSON carries `total_cost_usd`, `usage`,
  `modelUsage` (with `costBasis: "list"`), `session_id`, `num_turns`, `terminal_reason`.
  A trivial prompt cost about $0.005 (36k tokens of context, mostly cache creation: project
  instructions, tool definitions, hooks).
- `claude --bare ...` fails (`terminal_reason: api_error`, zero tokens): it reads only an API
  key or `apiKeyHelper`, not the OAuth login. **Unusable here.**
- `claude -p ... --setting-sources "" --strict-mcp-config --disable-slash-commands` works with
  the same auth, costs about $0.0015 and 22.6k tokens of context. With no setting source it
  loads no hooks and no telemetry env, so the stage does not run memory-recall or
  `cc-obs-ledger`, and does not export Claude Code telemetry unless the runner puts `OTEL_*`
  in the process environment. The stage's own cost then comes from the result JSON
  (`total_cost_usd`), and the `review.run=1` attribute is a safeguard if telemetry is added.
- Not tested: behaviour at the budget ceiling (needs a prompt that exceeds it).

### S2 store configs and OTLP round trip (T006, 2026-10-09)

Run natively from nixpkgs (tempo 2.10.5, loki 3.7.7, prometheus 3.12.0; the pinned images
are one patch newer) with the configs in `spike-configs/`. This proves the config keys and
the ingest paths; it does not test container networking (that stays a manual task, T027).

- `promtool check config`: valid. Loki `-verify-config`: valid. Tempo `-config.verify`: exit 0.
- **Prometheus**: `--web.enable-otlp-receiver` accepts OTLP/HTTP JSON at
  `/api/v1/otlp/v1/metrics`. `otlp: promote_resource_attributes: [host, review.run,
  repository]` works. Result series:
  `claude_code_token_usage_tokens_total{host, job="claude-code", repository, review_run="1",
  type="input"}`. Notes: the metric name gains the unit and `_total`
  (`claude_code.token.usage` with unit `tokens` becomes `claude_code_token_usage_tokens_total`);
  **dots in attribute names become underscores, so `review.run` is queried as `review_run`**;
  `service.name` becomes `job`. Update queries and the exclusion rule accordingly.
- **Loki**: OTLP/HTTP logs at `/otlp/v1/logs` (204). The record came back under
  `{service_name="claude-code"}` with `host`, `event_name`, `tool_name` and `severity_text`
  as fields. Config keys used (`limits_config.retention_period`, `compactor.retention_enabled`,
  `compactor.delete_request_store`, ingestion limits) are accepted.
- **Tempo**: OTLP/HTTP traces on the moved receiver port 14318 (`/v1/traces`, 200); the trace
  was returned from `/api/traces/<id>`. `compactor.compaction.block_retention: 720h` is
  accepted. Readiness takes about 15 s after start.

**Decision for T056**: review stages run with `--setting-sources ""`, `--strict-mcp-config`
and `--disable-slash-commands`, with `OTEL_RESOURCE_ATTRIBUTES=review.run=1` set anyway.
