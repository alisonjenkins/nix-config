---
id: "0011"
host: Alisons-MacBook-Pro
date: 2026-11-11T09:30:20Z
finding: 2026-11-03-Alisons-MacBook-Pro#1
decision: build
reason: "the 2026-11-02 outage was never flagged anywhere and telemetry during it was silently dropped (no local OTLP retry queue); added a sustained-threshold liveness check (10 min, 24h re-notify) to the existing disk guard so a future outage surfaces without being noisy"
metric: { question: unused-signals, key: stack-outage-2026-11-02, baseline: null, unit: n/a }
acted_on: "nix-config#934"
outcome: null
outcome_review: null
---
The 2026-11-02 review ran during a multi-hour podman-machine outage that produced no
alert of any kind; telemetry for that window was silently dropped rather than queued and
retried. Added a stack-liveness check to the observability-stack guard script
(`home/modules/observability-stack/scripts.nix`): readiness probes against
Prometheus/Loki/Tempo, a 10-minute sustained-down threshold to avoid flapping, causal-order
reporting (names the first store that failed its readiness check), and a 24h re-notify cap
so a prolonged outage doesn't repeat-notify. Shipped with 27 passing bats tests and
documented in `docs/observability-stack.md`. This is the one finding from this review
already acted on, via `nix-config#934`.
