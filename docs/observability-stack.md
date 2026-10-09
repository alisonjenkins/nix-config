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

## What is collected, and what is not

Claude Code's own telemetry (metrics, events, beta traces) goes to the collector. The
`cc-obs-ledger` hook adds per-turn context size, cache hit ratio, the fixed-context
split and keyed hashes of tool inputs. `memory-recall` adds its recall records.

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
```

The runtime (podman, containers, real ingest) is not covered by CI; the manual steps
are in the spec's `quickstart.md`.

## Known limits

- The review runner and its schedule (ADR 0037, spec T056 and T059) are not built yet.
  Token reviews are run by hand with `cc-obs-query` or `cc-obs-query digest --baseline`.
- Loki-backed `cc-obs-query` commands page through a bounded number of records. A
  truncated answer is marked as truncated and gives a `next` offset; its figures are a
  lower bound until the rest is read.
- Skill and MCP server names are kept as metric labels, so cost can be attributed to
  them. Only tool parameters, tool input, the full command and file path are dropped by
  default.

## Troubleshooting

| Symptom | Look at |
|---|---|
| Nothing starts | `systemctl --user status observability-stack` (Linux) or `~/.local/state/observability-stack/stack.log` (macOS); the script names a missing podman or a port already in use |
| Grafana shows no data | `curl http://127.0.0.1:4318/` reaches the collector? Claude Code reads `OTEL_*` only from user-level settings, not a project's `.claude/settings.json` |
| Disk budget exceeded | `cat ~/.local/state/observability-stack/guard.json`: `over` means the stores passed `maxDiskGB`; ingestion is still running |
| Hook problems | `~/.local/state/cc-obs-ledger/ledger.log` |
