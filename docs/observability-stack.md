# Observability stack

Local Loki (logs), Tempo (traces), Prometheus (metrics) and Grafana (UI), with an
OpenTelemetry Collector in front, running in containers from one declaration on
NixOS, non-NixOS Linux and macOS. Purpose: see where Claude Code spends tokens and
turn that into decisions about better tools. Design and rationale:
[`specs/007-local-observability-stack/`](../specs/007-local-observability-stack/spec.md),
ADRs [0034](adr/0034-observability-pod-via-podman-kube-play.md) and
[0035](adr/0035-disk-budget-reported-not-enforced.md).

## Turn it on

Home Manager module `self.homeModules.observability-stack`:

```nix
modules.observabilityStack.enable = true;
```

On NixOS the host also needs rootless podman (`modules.podman.enable = true`); the
module fails evaluation and says so if it is missing. Everything else has defaults.

| Option | Default | Meaning |
|---|---|---|
| `retentionDays` | 30 | Loki, Tempo and Prometheus |
| `maxDiskGB` | 20 | Disk budget; the guard reports going over it, ingestion never stops |
| `budgetSplitGB` | 4 / 7 / 7 | Prometheus / Loki / Tempo; must sum to 90% of the budget or less |
| `ports` | 3000 3100 3200 9090 4317 4318 | Grafana, Loki, Tempo, Prometheus, OTLP gRPC, OTLP HTTP |
| `listenAddress` | `127.0.0.1` | Anything else also needs `exposeBeyondLoopback = true` |
| `claudeCode.*` | on | Point Claude Code's telemetry at the collector |
| `podmanMachine` | `observability`, 2 CPUs, 4096 MiB, 30 GiB | macOS only: the stack's own podman machine, separate from Colima or any default machine. Sizing applies at creation only; to change it run `podman machine rm <name>` first (data lives in the data dir, not the VM). podman runs one machine at a time on macOS, so the stack will not start while another machine is running and the log names it; stop it or set `name` to it. This follows podman's documentation and is not yet verified on the owner's Mac (spike T005) |

Open Grafana at `http://localhost:3000`. Browsing via `http://127.0.0.1:3000` is redirected to localhost by design, to block DNS-rebinding attacks from web pages. This is not verified against a running Grafana yet; quickstart section 4 will check it. Client tools read ports from
`~/.config/cc-obs/endpoints.json`, which the module writes.

## Weekly token review

Off by default. `modules.observabilityStack.review.enable = true` installs a systemd user
timer (Linux) or launchd calendar interval (macOS) that runs `observability-stack-review`
on `review.schedule` (default `Mon 06:00`; macOS accepts only `<Day> HH:MM`). It needs the
Claude Code CLI on the service's `PATH` (`review.claudeCommand`; set it to `""` for a
no-model run that builds only the baseline digest) and the stack running.

| Step | What happens |
|---|---|
| Window | 7 days, or the days since the newest findings file's period end when that is longer, so a week whose stage 2 failed is covered again (with no model, the newest digest is used instead) |
| Stage 1 | `review.digestModel` runs `cc-obs-query` and replies with a digest; the runner validates it with `cc-obs-query digest --write`. A nonzero exit, a budget stop or a rejected digest falls back to `digest --baseline` (`stage1: "baseline"`) |
| Stage 2 | `review.analysisModel` reads only the digest, with no tools, and writes at most 5 findings. The runner rejects output that is empty, over 16 KiB, or not `## 1.` to `## 5.` headings, and records a failure instead of a findings file. Stage 1 is limited to the Bash tool and the `cc-obs-query` subcommands digest --baseline, top, tool, session and repeats |
| Spend | `--max-budget-usd` per stage from `review.maxBudgetUSD.{digest,analysis}`; each stage runs with `--setting-sources ""`, `--strict-mcp-config`, `--disable-slash-commands` and `review.run=1` appended to `OTEL_RESOURCE_ATTRIBUTES` |
| Output | `review.stateDir`: `digests/<date>-<host>.json`, `findings/<date>-<host>.md` (own_cost_usd is the two stages' reported cost), `failures/<time>-<stage>.json` when a stage fails. Never inside a repository, never committed; promote a findings file into `docs/token-efficiency/reviews/` by hand |

## What is collected, and what is not

Claude Code's own telemetry (metrics, events, beta traces) goes to the collector. The
`cc-obs-ledger` hook adds per-turn context size, cache hit ratio, the fixed-context
split and keyed hashes of tool inputs. `memory-recall` adds its recall records.

Two `cc-obs-query top` rankings have a definition worth knowing:

- `top subagent` has one row per agent and model, referenced as `subagent:<agent>@<model>`;
  `--format detailed` shows the model as its own field.
- `top session --by cache-hit` ranks sessions by prompt-cache hit ratio, lowest first. The
  ratio is weighted by tokens: cacheRead divided by cacheRead + cacheCreation + input,
  each summed over the window with `increase()`. It replaces the earlier unweighted mean of
  the per-request `cc_obs_ledger_cache_hit_ratio` gauge, which let one-request cold starts
  top the list; that mean is not reachable any more. Sessions with fewer than
  `--min-requests` requests (default 5, counted from the ledger's `cc_obs_ledger_requests_total` counter, one per API request; against a ledger that predates it the CLI falls back to counting cache-hit series and reports a gap) are
  left out. The `cache_hit_ratio` detail on plain `top session` uses the same definition.

Prompt text, responses, tool parameters and tool inputs are **not stored by default**:
Claude Code does not send them, and the collector deletes them if something does.
`claudeCode.capturePrompts` and `claudeCode.captureToolDetails` turn each on.
Tool-input hashes use a per-host key kept in `~/.local/state/cc-obs-ledger/hmac.key`.

## Disk

Prometheus caps itself by size and discards its oldest blocks when full. Loki and Tempo
only expire by age, so a guard checks the data directories every five minutes against
`maxDiskGB`. Over the budget it never stops ingestion; it writes
`~/.local/state/observability-stack/guard.json` (`ok` or `over`, back to `ok` below 90%)
and reports through the `observability_guard_over_budget` metric, the stack-health
dashboard, a session-start notice and a desktop notification (at most once per 24 h).

## Checks

```bash
nix build .#checks.x86_64-linux.observability-stack-render           # rendered pod, ports, retention, hooks, settings
nix build .#checks.x86_64-linux.observability-stack-config-validate  # real loki, tempo, prometheus, collector accept the configs
nix build .#checks.x86_64-linux.observability-stack-redaction-default  # real collector drops canary prompt/tool text
nix build .#checks.x86_64-linux.observability-stack-redaction-prompts  # canary prompt text is dropped unless capturePrompts is on
nix build .#checks.x86_64-linux.observability-stack-redaction-tools    # canary tool parameters and inputs are dropped unless captureToolDetails is on
nix build .#checks.x86_64-linux.observability-stack-guard            # disk guard: state file, no collector stop, notifications, metrics
nix build .#checks.x86_64-linux.observability-stack-review           # review runner: stages, baseline fallback, failure records, catch-up
```

The runtime (podman, containers, real ingest) is not covered by CI; the manual steps
are in the spec's `quickstart.md`.

## Delegated Gemini calls

`delegate-to-gemini.sh` (the `delegation` skill) sends one span per call to the
collector, a child of the Claude Code tool span that ran it, and appends the same
record to `~/.local/state/delegate/gemini-calls.jsonl`. Why and how: ADR 0046. In
Grafana's Tempo, group by the session that asked for the work:

```
{ resource.service.name = "delegate-to-gemini" } | select(span.claude.session_id, span.gen_ai.request.model, span.delegate.outcome, span.gen_ai.usage.input_tokens)
```

`span.delegate.outcome` is `success`, `denied`, `error`, `auth_missing`, `quota`,
`transient_exhausted` or `model_rejected`. Tokens and duration come from agy's JSON
envelope; there is no cost, since agy bills a plan quota (`agy -p /usage`).
`DELEGATE_TELEMETRY=off` turns it off; `DELEGATE_OTLP_ENDPOINT` overrides the endpoint.

## Known limits

- The review runner has only been run against fake `claude` and `cc-obs-query` commands
  (the `observability-stack-review` check). No real model or live stack has run it yet;
  that is the manual first review (spec T061). Run it by hand with
  `observability-stack-review` (it is on `PATH` once `review.enable` is set).
- Loki-backed `cc-obs-query` commands page through a bounded number of records. A
  truncated answer is marked as truncated and gives a `next` offset; its figures are a
  lower bound until the rest is read.
- Skill and MCP server names are kept as metric labels, so cost can be attributed to
  them. Only tool parameters, tool input, the full command and file path are dropped by
  default. The ledger uses them for `cc_obs_ledger_skill_listed_tokens{skill_name}` and
  `cc_obs_ledger_mcp_server_connected{mcp_server_name}`; skill descriptions and MCP
  instruction text are measured or counted, never sent.
- The ledger reads both from the transcript's `skill_listing` and
  `mcp_instructions_delta` attachments, so they appear at the first Stop hook after
  Claude Code writes them (and again if a later Stop sees a new one). Only MCP servers
  that ship instructions are named there. `cc_obs_ledger_cache_creation_tokens` and
  `cc_obs_ledger_seconds_since_prev_request` carry the labels of
  `cc_obs_ledger_context_tokens`; the gap is absent for a session's first request.

## Troubleshooting

| Symptom | Look at |
|---|---|
| Nothing starts | `systemctl --user status observability-stack` (Linux) or `~/.local/state/observability-stack/stack.log` (macOS); the script names a missing podman or a port already in use |
| Grafana shows no data | `curl http://127.0.0.1:4318/` reaches the collector? Claude Code reads `OTEL_*` only from user-level settings, not a project's `.claude/settings.json` |
| Disk budget exceeded | `cat ~/.local/state/observability-stack/guard.json`: `over` means the stores passed `maxDiskGB`; ingestion is still running |
| Hook problems | `~/.local/state/cc-obs-ledger/ledger.log` |
