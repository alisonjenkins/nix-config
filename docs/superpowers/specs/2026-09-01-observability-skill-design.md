# `observability` skill family — design

## Problem

There is no skill for debugging or improving a *live* system through an
observability platform. `debugging` carries the general method (reproduce,
probe the closest layer, positive control, distrust green signals) but says
nothing about how to apply that through Datadog or Grafana/LGTM. `infra`
covers deploying and mutating live infrastructure, not reading its telemetry.
`programming/observability.md` covers *writing* instrumentation into code,
not investigating with it afterward. Work uses Datadog today with a possible
future move to the Grafana LGTM stack (Loki/Grafana/Tempo/Mimir); personal
infrastructure already runs most of LGTM plus Prometheus directly. Both need
to be usable now.

## Goals

- One family that teaches: how to investigate a live system's performance or
  reliability problem through an observability platform, and how to improve
  observability itself (close gaps, design better alerts/dashboards, control
  cost) as a deliberate activity, not just a side effect of firefighting.
- Platform-agnostic method, separated from platform-specific tool usage, so
  the method transfers between Datadog (work) and Grafana/LGTM/Prometheus
  (personal), and survives a future platform migration.
- No duplication of `debugging`'s method, `infra`'s ask-before-mutating rule,
  or `programming/observability.md`'s instrumentation conventions — all three
  are cross-referenced, not restated.
- A raw query against a real observability platform can return thousands of
  lines and blow through a session's context for what should be a one-line
  answer ("which error dominates," "did this regress vs an hour ago"). Ship
  tooling that reduces platform output to what an investigation actually
  needs *before* it reaches Claude, not guidance alone asking Claude to
  remember to do that by hand every time.

## Non-goals

- Incident-response process (paging rotations, postmortem templates,
  comms during an outage). Out of scope; a candidate for a future skill if it
  becomes a recurring need.
- Hardcoded instance URLs, API keys, or org-specific dashboard IDs. Per the
  shared-machine portability rule, that detail belongs in memory or local
  config, never in a skill file that ships to every machine.
- Inventing exact CLI flag syntax for `pup` that cannot be verified. The
  Datadog file teaches query/investigation *patterns* and points at
  `pup --help`/`pup <subcommand> --help` for the current flag surface, rather
  than asserting flags from training data that may be stale or wrong.

## Structure

```
home/skills/observability/
  SKILL.md                 — purpose, cross-references, routing table
  investigation.md         — platform-agnostic investigation method
  improving.md              — closing gaps, alert/dashboard design, SLOs, cost
  platforms/
    datadog.md              — pup CLI + logs/APM/metrics/monitors
    grafana-lgtm.md           — LogQL/PromQL/TraceQL/Grafana API + Prometheus

pkgs/obs-cli/                — Rust CLI: reduces platform output before Claude sees it
```

This mirrors the existing family pattern (`programming/languages/*.md` for
the one per-language dimension, flat by-concern files alongside it): platform
is the one dimension here, so it gets its own subdirectory; investigation
method and improvement practice are by-concern and stay flat. `obs-cli` is a
new package under `pkgs/`, following this repo's existing convention for
custom software, not part of the skill directory itself — the skill files
teach when and how to reach for it.

## Division of responsibility

| Concern | Owned by | This family's role |
|---|---|---|
| General debugging method | `debugging` | Apply it through a specific platform's tools; `investigation.md` explicitly maps "probe the layer closest to the fault" and "distrust a green signal" (`debugging/false-signals.md`) onto observability-platform practice. |
| Ask before mutating live infrastructure | `infra` | Creating/editing a monitor, dashboard, or alert *is* a mutation. `improving.md` and both platform files point back to `infra` rather than restating the rule. |
| Writing instrumentation (log fields, levels, spans) | `programming/observability.md` | The other end of the same loop: an investigation that hits a missing signal produces a gap-closing follow-up that *is* `programming/observability.md`'s job. Cross-linked both directions. |

## Content plan

### `SKILL.md`
Standard family parent: one-paragraph purpose, the division-of-responsibility
table above (condensed), and the routing table (by-concern: investigation vs
improving; by-platform: datadog vs grafana-lgtm). Description explicitly
states the negative case — not for instrumenting your own code, not for
deploying/mutating infrastructure — since both neighbours are easy to
confuse with this one.

### `investigation.md`
- **Symptom-first triage.** Start from what's actually reported (latency,
  error rate, saturation — RED/USE framing) rather than guessing a cause;
  the symptom tells you which signal to check first.
- **Correlate across signals.** A trace ID (or equivalent request/job
  correlation ID — same concept `programming/observability.md` mandates
  producers thread through) is the thread that ties a slow request in a
  dashboard to its specific trace to its specific log lines. Teach pulling
  that thread, not treating logs/traces/metrics as separate silos.
- **Distrust the dashboard.** Cross-reference `debugging/false-signals.md`
  directly: a green panel can mean "no data," not "healthy." Know the
  difference between an empty query and a query returning zero.
- **Reporting a finding.** Mirrors `review`'s "phrasing a finding": what
  was checked, what it showed, what's still unconfirmed — so an
  investigation's output is usable by someone who wasn't there, the same
  reasoning behind observability-driven development in the first place.

### `improving.md`
- **Closing gaps found during investigation.** When triage hits a dead end
  because a signal doesn't exist, that's the deliverable — not "investigation
  failed," but "found the next thing to instrument." Hands off to
  `programming/observability.md` for the actual instrumentation work.
- **Alert design.**
  - **Avoid flapping**: sustained-condition thresholds (a for-duration/
    pending period so a single noisy sample doesn't fire), hysteresis (a
    lower clear-threshold than trigger-threshold), and sizing the evaluation
    window against the signal's natural noise.
  - **Exception-based, not surveillance-based**: silence should mean
    healthy. Prefer anomaly/outlier/forecast detection or burn-rate alerts
    over static thresholds on naturally variable signals. "Someone has to
    watch a dashboard to notice this" is itself a finding — the fix is a
    monitor, not a habit.
  - **Priority routes, not just fires.** Severity should map to real
    urgency and route accordingly (page vs ticket vs silent log); a flood of
    unprioritized alerts trains people to ignore all of them.
  - **Point at cause, not symptom, wherever the causal chain is knowable.**
    Alert on the most causally-proximate signal available (a specific
    dependency's error rate) over a downstream aggregate ("CPU high"), and
    use the platform's correlation features (Datadog related signals,
    Grafana exemplars linking metrics→traces) to hand the responder a lead.
    Explicitly "where possible" — not always knowable ahead of time.
- **Dashboard design.** Built for the question it answers, not a wall of
  every metric that exists; the RED/USE framing from `investigation.md`
  as the default panel layout for a service dashboard.
- **SLOs / error budgets.** Defining and reviewing them, and how burn-rate
  alerting (above) is the practical link between an SLO and an actual page.
- **Cost control.** Logging, metrics, and traces are billed/stored resources
  and a bad default multiplies them silently:
  - **Message templating**: a stable template ID/enum for a known error or
    event type plus its structured detail fields as separate attributes,
    instead of a fresh free-text interpolated string per occurrence — the
    backend indexes the template once rather than paying to store and index
    it fresh every time. The cost-driven reinforcement of
    `programming/observability.md`'s "structured fields, not an interpolated
    sentence."
  - **Cardinality discipline**: a high-cardinality value (user ID, raw URL
    with path params, request ID) as a metric label or Loki log label
    explodes the index — Loki in particular is architecturally built around
    low-cardinality labels, with high-cardinality detail belonging in the
    parsed log body, not the label set. Prometheus/Mimir/Datadog tag
    cardinality is billed the same way.
  - **Sampling**: head- vs tail-based trace sampling; log sampling for
    high-volume repetitive events (keep 100% of errors, sample the routine
    successful ones).
  - **Retention tiering**: shorter retention for verbose/debug-level data,
    longer for rolled-up/aggregated data.
  - **Log level discipline in production**, reinforced from the cost angle
    on top of the readability angle `programming/observability.md` already
    covers.

### `platforms/datadog.md`
- Logs: search/explorer syntax patterns, facets, log-based metrics.
- APM/traces: service maps, trace search, flame graphs, span analysis.
- Metrics/dashboards: metrics explorer, querying existing dashboards.
- Monitors: reading alert history and understanding what fired and why,
  applying `improving.md`'s alert-design principles when authoring one.
- The `pup` CLI: usage *patterns* (search, filter, correlate by trace ID)
  with a pointer to `pup --help`/`pup <subcommand> --help` for exact current
  flags, not a hardcoded flag reference.
- Mentions `claude-dd` (this repo's wrapper loading the `pup-claude` plugin's
  49 agents/~14 skills) as an option for deeper pup-specific work, without
  this skill depending on it — everything here works in a normal session.

### `platforms/grafana-lgtm.md`
- **Loki** (LogQL): query patterns, the low-cardinality-labels constraint
  from `improving.md`'s cost section restated as a Loki-specific design rule.
- **Grafana**: the HTTP API for dashboards/panels, reading and building
  dashboards per `improving.md`'s dashboard-design section.
- **Tempo** (TraceQL): trace search and span analysis, the Grafana
  exemplars link from metrics to traces.
- **Mimir/Prometheus** (PromQL): shared query language, but covered as two
  operationally distinct things — Mimir as Prometheus-compatible long-term
  storage/multi-tenant remote-write target, vs a directly-run Prometheus
  with its own Alertmanager, scrape targets, and service discovery. The
  remote-write path from a local Prometheus into Mimir, when both are
  present, gets its own note since that's the common personal-infra shape.
- No hardcoded instance URLs/auth — generic query/API guidance only.

### `pkgs/obs-cli` — token-efficient analysis tooling

A single Rust binary (`obs`), one CLI with subcommands per platform, sharing
one reduction engine so the four reduction techniques are implemented once
and available everywhere instead of duplicated per platform:

```
obs datadog logs    <query>  [--mode ...] [--group-by ...] ...
obs datadog metrics <query>  [--mode ...] ...
obs datadog traces  <query>  [--mode ...] ...
obs lgtm logs        <logql>  [--mode ...] ...   # Loki
obs lgtm metrics     <promql> [--mode ...] ...   # Mimir/Prometheus
obs lgtm traces      <traceql>[--mode ...] ...   # Tempo
```

Shared flags across every query subcommand:
- `--mode aggregate|topn|histogram|diff|raw` — **`raw` is never the
  default**; an explicit opt-in with a hard row cap, so "give me everything"
  stays possible without it silently becoming the common path.
  - `aggregate`: group-by counts (e.g. per error type, per status code).
  - `topn`: the N most significant contributors plus a total count.
  - `histogram`: time-bucketed rate/count instead of a flat event list.
  - `diff`: current window against a baseline window, suppressing
    steady-state noise, surfacing only what changed.
- `--group-by <field>`, `--top <n>`, `--bucket <duration>`,
  `--baseline <duration>` — mode-specific parameters.
- `--format json|table` — compact by default; JSON for further piping,
  table for direct reading. Never pretty-printed raw API responses.

Auth/config is read from existing credential storage (this repo's sops-nix
secrets, or the ambient Datadog/Grafana env the work environment already
provides) — never hardcoded, per `security.md`. Output is deliberately
lossy: it answers "what does this query need to tell an investigator," which
is the whole reduction goal, not "reproduce the platform's UI in a
terminal."

Building this is real software, not skill prose — it follows the
`programming` skill in full: `rust.md`'s guard rails (deny-by-default
panic-class lints, `[lints.clippy]`), one error enum per fallible function
(a distinct variant per HTTP call, per parse step, per auth failure — this
tool talks to two different external APIs, so error-site precision matters
for its own debuggability), `tracing` for its own structured logging (this
observability tool follows `observability.md` on itself), and `testing`'s
TDD loop with the platform HTTP clients behind a trait/interface so the
reduction logic (aggregate/top-N/histogram/diff) is unit-testable against
fixture responses without hitting a real Datadog/Grafana instance in CI.

## Validation

Two different kinds of validation for two different kinds of deliverable:

- **Skill content** (`home/skills/observability/`): the `skill-authoring`
  discipline — confirm the parent's description carries trigger vocabulary
  for every child (platform names, "alert", "dashboard", "SLO",
  "cardinality", "Datadog", "Grafana", "Loki", "Prometheus", "LGTM"),
  confirm no content duplicates what `debugging`/`infra`/
  `programming/observability.md` already own, and a read-through for the
  usual placeholder/contradiction/scope check.
- **`obs-cli`**: real code, real tests. `cargo test` covering the reduction
  engine against fixture data for all four modes, `cargo clippy --all-targets
  -- -D warnings` clean, and `just build` (or the equivalent package build)
  succeeding before this is considered done — per the `testing` and
  `programming` skills, not a special exemption for being "just a helper
  tool."

## Open questions for the implementation plan

None blocking — the four sub-areas of `improving.md`, the platform split,
the cost-control content, and `obs-cli`'s shape (unified Rust CLI, four
reduction modes, per-platform subcommands) are all settled. The
implementation plan should decide:

- **Sequencing**: skill docs and `obs-cli` are different kinds of work
  (markdown authoring vs a real Rust package with its own test suite) —
  the plan should treat them as separate phases/PRs rather than one
  monolithic change, the same way the `programming` skill's observability/
  performance additions each landed as their own atomic PR. Whether skill
  docs land before, after, or interleaved with `obs-cli` is the plan's call;
  the skill files can reference `obs-cli` by name before it exists (the
  `programming` skill family already has precedent for a doc referencing a
  not-yet-built follow-up in `PENDING.md`).
- File-by-file writing order for the skill docs (parent + routing first, so
  each child can be reviewed against a stable routing table).
- Whether `platforms/*.md` needs its own further split later if either grows
  past what one file should carry (see `skill-authoring/context-budget.md`).
- `obs-cli`'s exact HTTP client trait boundary and fixture format for the
  reduction-engine tests — a design-level decision, not architecture, left
  to the plan/implementation.
