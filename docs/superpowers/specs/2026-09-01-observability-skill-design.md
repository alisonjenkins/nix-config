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

- Paging rotations and live incident comms (who gets paged, how a
  channel/bridge is run during an active outage). Out of scope; a
  candidate for a future skill if it becomes a recurring need.
  **Postmortem practice itself — reconstructing what happened from
  observability data, blameless write-up, action-item tracking — is
  in scope**, covered by `postmortems.md`; this exclusion is narrower
  than the original draft, which lumped postmortems in with paging.
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
  coverage.md                — finding what needs monitoring, spotting gaps
  postmortems.md              — reconstructing an incident, blameless write-up
  platforms/
    datadog.md              — pup CLI + logs/APM/metrics/monitors
    grafana-lgtm.md           — LogQL/PromQL/TraceQL/Grafana API + Prometheus

pkgs/sift/                — Rust CLI: reduces platform output before Claude sees it
```

This mirrors the existing family pattern (`programming/languages/*.md` for
the one per-language dimension, flat by-concern files alongside it): platform
is the one dimension here, so it gets its own subdirectory; investigation
method and improvement practice are by-concern and stay flat. `sift` is a
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
table above (condensed), and the routing table (by-concern: investigation,
improving, coverage, postmortems; by-platform: datadog vs grafana-lgtm).
Description explicitly states the negative case — not for instrumenting your
own code, not for deploying/mutating infrastructure — since both neighbours
are easy to confuse with this one.

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

### `coverage.md`

Proactive, not reactive: finding what *should* be monitored before an
investigation ever needs it, across a VM/host or a set of cloud resources
making up a system. Distinct from `improving.md`'s "closing gaps found
during investigation" — that's reactive (an investigation already hit the
dead end); this is the audit that finds the dead end before anyone falls
into it.

- **Enumerate before you check coverage.** You cannot know what's
  unmonitored without first knowing what exists. Don't hand-roll resource
  enumeration — lean on existing inventory tooling:
  - **Host/VM level**: `systemctl list-units` for running services,
    `osquery` (SQL-queryable OS state, including a `systemd_units`
    table and listening sockets) for a scriptable structured inventory
    beyond what `systemctl` alone gives you.
  - **Cloud resources**: `terraform state list` (or `terraform show
    -json`) when the system is IaC-managed — the fastest, most accurate
    inventory of what's *supposed* to exist, and ties directly into
    `infra`'s "IaC is the source of truth" principle. CloudQuery or
    Steampipe (SQL-queryable cloud-provider APIs) for a live inventory
    independent of IaC state, useful for catching drift — a resource
    that exists in the cloud but not in Terraform state is itself a
    finding, the observability-adjacent cousin of `infra/kubernetes.md`'s
    "a `kubectl apply` outside GitOps is lost on next reconcile."
- **Cross-reference against instrumentation, per platform:**
  - **Datadog** ships real coverage tooling for this already — Software
    Catalog and Universal Service Monitoring surface services with no
    telemetry/SLOs/monitors, Resource Catalog and Cloud Security Posture
    Management do the same for cloud resources. Use these directly
    before reaching for anything else; they only see what Datadog was
    already pointed at, so a resource entirely outside Datadog's reach
    still needs the enumeration step above to be found at all.
  - **Grafana/Prometheus** has no packaged equivalent. Cross-reference
    Prometheus's own target list (`/api/v1/targets`) against the
    enumerated resource/service list by hand, and treat an absent `up`
    series for an expected target as a gap in its own right — not just
    "no data," an actual finding (see `investigation.md`'s "distrust the
    dashboard": a target that was never scraped and a target that's
    failing to scrape both show as missing data, so confirm which one
    you're looking at before reporting either as healthy or as down).
- **Report gaps the same way as any other finding** (`investigation.md`'s
  "reporting a finding" format): what was enumerated, what coverage was
  found or missing for each, ranked by what a gap there would actually
  cost if it went unnoticed during an incident — a missing alert on a
  primary database's connection pool ranks above a missing dashboard
  panel for a background batch job.
- **Tooling**: no existing tool does the full enumerate → cross-reference
  → report loop across both cloud resources and host services for both
  Datadog and Grafana/Prometheus (confirmed by research before writing
  this section — see the design conversation). `sift audit` (see
  `pkgs/sift`) is the fast-follow that closes this: reusing existing
  enumeration tooling (Terraform state, CloudQuery/Steampipe, osquery)
  rather than reinventing inventory, adding only the coverage
  cross-reference and gap-report layer this file describes.

### `postmortems.md`

Full postmortem practice: reconstructing what happened, writing it up
blamelessly, and tracking the resulting action items. Paging rotations and
live incident comms stay out of scope (see Non-goals) — this file starts
once the incident is over and the question becomes "what happened and what
do we do about it."

- **Reconstruction is `investigation.md`'s method, applied after the
  fact, for the whole incident rather than one symptom.** Build the full
  timeline by pulling the same correlation thread (trace ID → traces →
  logs) across the entire incident window, not just the first anomaly
  found — an incident with one root cause commonly has multiple visible
  symptoms across different services, and a postmortem that stops at the
  first one found produces an incomplete or wrong root cause.
- **Distrust the dashboard applies retroactively too.** A metric that
  looked fine during the incident because its query was scoped wrong or
  its time range defaulted somewhere unhelpful needs re-checking with
  the benefit of hindsight — `investigation.md`'s false-signal checks are
  not a one-time gate you clear during the incident, they're worth
  re-running when building the postmortem timeline itself.
- **Blameless means the timeline explains *what* the system and its
  operators did and why it made sense at the time, not who to fault.** A
  postmortem that names an individual as the cause has usually stopped
  one level too shallow — "engineer X pushed a bad config" is an
  observation, not a root cause; the root cause is whatever let a bad
  config reach production undetected (missing validation, missing
  staging parity, missing alert on the exact signal that would have
  caught it — which is itself a `coverage.md`-style gap worth naming
  explicitly in the postmortem's follow-up items).
- **Action items are gap-closing, and they route to the file that owns
  the gap.** A missing instrumentation signal found while reconstructing
  the timeline routes to `programming/observability.md` (write the
  instrumentation) via `improving.md`'s "closing gaps" section; a missing
  alert or monitoring coverage routes to `coverage.md`/`improving.md`'s
  alert-design section. The postmortem's job is to *find and route* the
  gap, not to re-derive how to fix it — this file does not duplicate
  either of those files' content.
- **A postmortem with no unresolved action items is a red flag, not a
  clean bill of health.** If reconstructing an incident revealed nothing
  worth fixing, either the reconstruction stopped too early or the
  incident really was pure bad luck with no systemic contributor — the
  latter is rare enough that it deserves stating explicitly rather than
  silently assumed.

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

### `pkgs/sift` — token-efficient analysis tooling

A single Rust binary (`sift`), one CLI with subcommands per platform, sharing
one reduction engine so the four reduction techniques are implemented once
and available everywhere instead of duplicated per platform:

```
sift datadog logs    <query>  [--mode ...] [--group-by ...] ...
sift datadog metrics <query>  [--mode ...] ...
sift datadog traces  <query>  [--mode ...] ...
sift lgtm logs        <logql>  [--mode ...] ...   # Loki
sift lgtm metrics     <promql> [--mode ...] ...   # Mimir/Prometheus
sift lgtm traces      <traceql>[--mode ...] ...   # Tempo
sift audit vm                  [--format ...] ...   # coverage.md's host-level gap audit
sift audit aws                 [--format ...] ...   # coverage.md's cloud-resource gap audit
```

`sift audit` is `coverage.md`'s tooling: it does not re-implement resource
enumeration — it shells out to or wraps existing inventory tooling
(`terraform state list`/`show -json`, CloudQuery or Steampipe, `osquery`)
and adds only the coverage cross-reference and gap-report layer, since
research confirmed no existing tool does that full loop across both cloud
resources and host services for both Datadog and Grafana/Prometheus. Not
part of the reduction engine below — it's a different kind of query
(enumerate-and-compare, not query-and-reduce a time-series/log platform) —
and is scoped as a fast-follow after the core reduction-engine MVP, same as
Datadog/Tempo support (see the implementation plan's fast-follow section).

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
TDD loop with each platform client split into a thin network-fetch function
and a pure parse function, so the parse logic (and the reduction logic
downstream of it: aggregate/top-N/histogram/diff) is unit-testable against
fixture responses without hitting a real Datadog/Grafana instance in CI —
resolved in the implementation plan as a fetch/parse split rather than a
full trait abstraction, since one implementation per platform doesn't need
the extra indirection (YAGNI).

## Validation

Two different kinds of validation for two different kinds of deliverable:

- **Skill content** (`home/skills/observability/`): the `skill-authoring`
  discipline — confirm the parent's description carries trigger vocabulary
  for every child (platform names, "alert", "dashboard", "SLO",
  "cardinality", "Datadog", "Grafana", "Loki", "Prometheus", "LGTM",
  "coverage", "audit", "postmortem", "incident"), confirm no content
  duplicates what `debugging`/`infra`/`programming/observability.md`
  already own, and a read-through for the
  usual placeholder/contradiction/scope check.
- **`sift`**: real code, real tests. `cargo test` covering the reduction
  engine against fixture data for all four modes, `cargo clippy --all-targets
  -- -D warnings` clean, and `just build` (or the equivalent package build)
  succeeding before this is considered done — per the `testing` and
  `programming` skills, not a special exemption for being "just a helper
  tool."

## Open questions for the implementation plan

None blocking — the four sub-areas of `improving.md`, the platform split,
the cost-control content, and `sift`'s shape (unified Rust CLI, four
reduction modes, per-platform subcommands) are all settled. The
implementation plan should decide:

- **Sequencing**: skill docs and `sift` are different kinds of work
  (markdown authoring vs a real Rust package with its own test suite) —
  the plan should treat them as separate phases/PRs rather than one
  monolithic change, the same way the `programming` skill's observability/
  performance additions each landed as their own atomic PR. Whether skill
  docs land before, after, or interleaved with `sift` is the plan's call;
  the skill files can reference `sift` by name before it exists (the
  `programming` skill family already has precedent for a doc referencing a
  not-yet-built follow-up in `PENDING.md`).
- File-by-file writing order for the skill docs (parent + routing first, so
  each child can be reviewed against a stable routing table).
- Whether `platforms/*.md` needs its own further split later if either grows
  past what one file should carry (see `skill-authoring/context-budget.md`).
- `sift`'s exact HTTP client trait boundary and fixture format for the
  reduction-engine tests — a design-level decision, not architecture, left
  to the plan/implementation.
