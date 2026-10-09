# Implementation Plan: Local Observability Stack

**Branch**: `007-local-observability-stack` | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-local-observability-stack/spec.md`

## Summary

A Home Manager module, `modules.observabilityStack` (`home/modules/observability-stack`),
renders one pod definition (Loki, Tempo, Prometheus, Grafana and an OpenTelemetry Collector)
and runs it with `podman kube play`: a systemd user service on Linux, a launchd agent on macOS.
Claude Code's built-in telemetry, `memory-recall`'s existing Loki/Tempo push and a small new
`cc-obs-ledger` hook tool (fixed-context and per-turn figures the built-in export lacks) all land
in it. A versioned review-question pack, the `cc-obs-query` CLI and a weekly unattended two-tier
review turn the data into ranked findings, which the owner turns into decision records. A
`token-efficiency` skill carries the method. The MCP-versus-CLI delivery choice is settled by
an experiment before the review tooling is finished.

## Technical Context

**Language/Version**: Nix (module, checks, renderers); Rust 2021 for `cc-obs-ledger` and `cc-obs-query`
(same toolchain as `scripts/retrieval-eval`); shell only as Nix-resolved wrappers; Markdown/YAML/JSON for review packs and records.

**Primary Dependencies**: podman (rootless on Linux, `podman machine` on macOS); pinned
images grafana 12.4.x, loki 3.7.x, tempo 2.10.x, prometheus v3.13.x,
otel-collector-contrib 0.162.x (digests fetched at implementation); `claude` CLI for the
scheduled review (`-p`, `--max-budget-usd`); existing `memory-recall`.

**Storage**: bind-mounted data directories per service under the OS data dir
(`$XDG_DATA_HOME/observability`, `~/Library/Application Support/observability`); review output
in a per-host state directory; decision records in the repository.

**Testing**: pure flake checks (bats in `runCommand`, following `flake-modules/obs-config-tests.nix`)
for rendered configs and for Linux and darwin home evaluation; `cargo test` with clippy/fmt
gates for the Rust tools; a manual quickstart per OS for runtime behaviour (named untestable glue).

**Target Platform**: NixOS (`ali-desktop` first), non-NixOS Linux via home-manager only,
macOS (`ali-work-laptop-macos`, hostname `Alisons-MacBook-Pro`).

**Project Type**: Nix module plus two small CLIs, a skill and a review workflow.

**Performance Goals**: telemetry export never delays a Claude Code prompt (detached,
best effort, 3 s timeouts); prompt latency within 5% (SC-005); a review finishes in under
10 minutes of owner attention (SC-009).

**Constraints**: loopback-only listeners; 30-day retention and 20 GB total cap by default;
no prompt or tool content stored by default; no secrets in the Nix store; no commits made
by the system.

**Scale/Scope**: one owner, a handful of hosts each running its own stack; low volume
(hundreds of prompts a day, thousands of tool calls).

Unresolved items are listed in [research.md](research.md) with the spike that closes each (S1 to S5).

## Constitution Check

*GATE: must pass before research; re-checked after design.*

| Principle | Status | How |
|---|---|---|
| I Atomic, revertable history | Pass | Tasks are split so each commit builds alone: module skeleton, then renderers, then each store, then Claude wiring, then tools, then skill. No AI attribution. |
| II Test first, evidence | Pass with named glue | Render/eval checks are written before the renderers and watched failing locally; the test and the change that satisfies it land in one commit, so no commit leaves a check red. Runtime on podman machine and real ingest cannot run in CI: named untestable glue, covered by `quickstart.md` evidence on one host per OS. |
| III IaC, live changes by consent | Pass | Everything is declared in the flake. `podman machine init` runs from the launchd agent on the owner's own host as part of activation, idempotent; no remote or shared system is touched. |
| IV Errors carry context | Pass | Start failures name the missing runtime or the port; the Rust tools return errors with operation and input; clippy `-D warnings`, no `unwrap` outside tests. |
| V Right altitude, single source | Pass | Ports, retention and endpoints are options referenced by the pod, the Claude env, `memory-recall` telemetry and the Grafana datasources. One pod definition for both OSes. Reuses `memory-recall`'s existing push rather than a second path. |
| VI Record the why | Pass | ADRs (next free numbers) for: pod via `kube play` on both OSes; disk budget reported, not enforced; two-tier unattended review; delivery mechanism once S4 decides. |
| VII Fork patches | N/A | No fork patch involved. |

Post-design re-check: still passes. The one soft spot is SC-014's size bound, reported by a
guard that never stops ingest, rather than enforced by a quota; recorded in an ADR and in
Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/007-local-observability-stack/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── module-options.md      # Nix options and what they render
│   ├── cc-obs-query.md             # cc-obs-query CLI and digest JSON
│   ├── cc-obs-ledger.md           # hook tool and the metrics/logs it emits
│   └── review-formats.md      # question pack, findings, decision record
└── tasks.md                   # /speckit-tasks, not created here
```

### Source Code (repository root)

```text
home/modules/observability-stack/
├── default.nix                # options, assertions, endpoints.json, wiring to claude-code and memory-recall
├── images.nix                 # pinned image tags and digests
├── pod.nix                    # renders the pod YAML from options
├── scripts.nix                # run and disk-guard scripts
├── configs.nix                # loki / tempo configs
├── collector.nix              # collector pipelines, redaction, prometheus config and recording rules
├── grafana.nix                # datasource and dashboard provisioning
├── disk-guard.nix             # disk guard script and package
├── review.nix                 # two-stage review runner
├── runner-linux.nix           # systemd user service + guard and review timers
├── runner-darwin.nix          # launchd agent (+ podman machine) + guard and review schedule
├── tests/                     # bats: disk-guard, collector-redaction, review-runner
└── dashboards/                # provisioned JSON: claude-code, token-cost, recall, stack-health

flake-modules/
├── home-modules.nix           # + observability-stack export
├── packages.nix               # + token-tools
└── observability-stack-tests.nix   # pure checks: render assertions, linux+darwin eval

pkgs/default.nix               # + token-tools = callPackage ./token-tools
pkgs/token-tools/              # packaging of the Rust workspace below
scripts/token-tools/           # Rust workspace, one crate per binary
├── cc-obs-ledger/             # SessionStart (census, notice) / Stop / SessionEnd hook tool
└── cc-obs-query/              # query library + CLI (Prometheus, Loki, Tempo) and review digest

specs/007-local-observability-stack/
├── spike-configs/             # working minimal configs from spike S2
└── evidence/                  # command output from the manual quickstart tasks

home/skills/token-efficiency/  # SKILL.md + review.md + tool-design.md (+ checklist)
docs/token-efficiency/
├── reviews/                   # promoted findings
├── decisions/                 # decision records
└── questions.yaml             # versioned review-question pack
docs/adr/                      # new ADRs
```

**Structure Decision**: one Home Manager module (works on NixOS, non-NixOS Linux and macOS
without a separate system module; a NixOS host only needs `modules.podman` enabled). Rust
tools live in a separate workspace under `scripts/` because `scripts/retrieval-eval` is a
different product. `memory-recall` gains metric emission and a session id but no new module.

## Delivery order (what `/speckit-tasks` should follow)

1. **Spikes first** (each closes an unconfirmed item; results go in `research.md`; S4 is the exception: it runs once the query library exists and before the review runner, see tasks T054):
   S1 `podman kube play` plus `podman machine` on macOS; S2 Tempo retention key names and Loki
   OTLP ingest; S3 transcript `usage` fields and the join key between events and spans;
   S4 MCP-versus-CLI experiment (FR-038); S5 `claude -p --max-budget-usd` unattended behaviour.
2. Failing render and eval checks, then the module that satisfies them (story 1).
3. Claude Code wiring and collector routes; verify one session end to end (story 2).
4. Recall metrics and session-id join in `memory-recall` (story 5).
5. `cc-obs-ledger` and cost-attribution dashboards (story 3, story 6).
6. `cc-obs-query` CLI, question pack, scheduled review, decision records (story 4).
7. Skill, written from the first manual review and S4's result (story 7).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Disk budget reported when exceeded (guard never stops ingest) instead of a hard quota | Loki and Tempo have no size cap; filesystem quotas are not portable across macOS and the Linux filesystems in use; losing new telemetry is worse than using more disk | Per-store limits alone cannot honour the 20 GB budget (SC-014); deleting store blocks ourselves risks corruption |
| Second OTLP/HTTP sender (in `cc-obs-ledger`) beside the one in `scripts/retrieval-eval` | `memory-recall`'s package builds from its own source directory, so sharing a crate would change that boundary and touch working code | Extracting a shared crate now costs more than ~100 duplicated lines; revisit at a third user (constitution V) |
| Two small Rust binaries | Fixed-context accounting needs the transcript; analysis needs bounded, cheap queries | A shell/jq pipeline would put unbounded output in front of the model, against the goal, and is untestable at the level the constitution requires |
