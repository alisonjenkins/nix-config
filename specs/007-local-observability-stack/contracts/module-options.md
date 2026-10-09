# Contract: `modules.observabilityStack` (Home Manager)

Off by default (FR-004). One option set on Linux and macOS (FR-002).

| Option | Type | Default | Meaning |
|---|---|---|---|
| `enable` | bool | `false` | The whole stack, Claude wiring and schedules |
| `retentionDays` | int | `30` | Applied to Loki, Tempo, Prometheus |
| `maxDiskGB` | int | `20` | Disk budget; reported by the guard when exceeded, never enforced (ingestion continues); Prometheus gets its own size flag from the budget split |
| `budgetSplitGB` | `{ prometheus; loki; tempo; }` | `{ 4; 7; 7; }` | Must sum to ≤ 90% of `maxDiskGB` (assertion); the rest is headroom for Grafana state and the collector queue |
| `ports` | `{ grafana; loki; tempo; prometheus; otlpGrpc; otlpHttp; }` | `3000 3100 3200 9090 4317 4318` | Single source: used by the pod, Claude env, `memory-recall`, Grafana datasources, `cc-obs-query` |
| `listenAddress` | str | `"127.0.0.1"` | Anything else needs `exposeBeyondLoopback = true` |
| `exposeBeyondLoopback` | bool | `false` | Explicit opt-in (FR-013) |
| `dataDir` | str | OS default (`$XDG_DATA_HOME/observability`, `~/Library/Application Support/observability`) | Bind-mount root |
| `podmanMachine` | `{ name; cpus; memoryMiB; diskSizeGiB; }` | `{ "observability"; 2; 4096; 30; }` | macOS only, ignored on Linux. Dedicated podman machine, isolated from Colima and the default machine; name must match `^[A-Za-z0-9][A-Za-z0-9_.-]*$` (assertion). Sizing is init-time only: `podman machine rm <name>` to change |
| `images` | attrs of `{ repo; tag; digest; }` | pinned values | Check fails on floating tag or missing digest (FR-003) |
| `claudeCode.enable` | bool | `true` | Writes the telemetry env into user-level Claude settings |
| `claudeCode.captureToolDetails` | bool | `false` | `OTEL_LOG_TOOL_DETAILS` and collector keeps `tool_parameters` |
| `claudeCode.capturePrompts` | bool | `false` | `OTEL_LOG_USER_PROMPTS` and collector keeps prompt text |
| `claudeCode.traces` | bool | `true` | Beta traces flag |
| `claudeCode.includeRepository` | bool | `true` | `OTEL_METRICS_INCLUDE_REPOSITORY=1`, needed for per-project attribution (spec FR-020) |
| `prices` | attrs model → `{ inputPerMTok; outputPerMTok; cacheReadPerMTok; cacheWritePerMTok; }` | list prices at implementation date | Cost estimates only (FR-022) |
| `ledger.enable` | bool | `true` | Installs `cc-obs-ledger` hooks |
| `review.enable` | bool | `false` | Weekly unattended review |
| `review.schedule` | str | `"Mon 06:00"` | systemd calendar / launchd interval |
| `review.digestModel` / `review.analysisModel` | str | `"haiku"` / `"opus"` | Tier models (FR-032) |
| `review.maxBudgetUSD` | `{ digest; analysis; }` | `{ 0.25; 2.0; }` | Passed as `--max-budget-usd` per stage (FR-031) |
| `review.notify` | bool | `true` | SessionStart one-line notice when findings are waiting (FR-031) |
| `review.stateDir` | str | `$XDG_STATE_HOME/token-review` | Digests and draft findings |

## Assertions (evaluation-time errors that name the cause and fix, FR-018)

- Budget split sums over 90% of `maxDiskGB`.
- Two `ports` entries equal, or a port in the known-used list (8080, 8110, 9100) without override.
- `listenAddress != 127.0.0.1` without `exposeBeyondLoopback`.
- On NixOS: the host config has `modules.podman.enable` (message names it).
- Any image missing a digest or using `latest`.

## What it renders

- One pod YAML (five containers, shared network namespace, only configured ports published on `listenAddress`).
- Store configs, collector pipeline, Grafana provisioning (datasources with trace↔log and trace↔metric links; dashboards from `dashboards/`).
- Runner: `observability-stack.service` (systemd user) or `org.nix.observability-stack` (launchd agent), restart on failure, start at login/boot.
- Disk guard: timer every 5 minutes; stops only the collector over the cap, resumes under 90% (R5).
- Claude settings (user-level `env`): `CLAUDE_CODE_ENABLE_TELEMETRY`, `OTEL_*` to the collector, content gates per the options above.
- `memory-recall.telemetry` defaults (`lokiUrl`, `tempoEndpoint`) pointed at the stack when both modules are enabled.
- Hooks for `cc-obs-ledger` (SessionStart, Stop, SessionEnd).
