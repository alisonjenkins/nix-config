# Observability Skill Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `observability` skill family (investigation method, improvement practice, proactive coverage auditing, postmortem practice, and Datadog/Grafana-LGTM-Prometheus platform guidance) to `home/skills/`, wired into the existing `programming`/`debugging`/`infra`/`review` skills without duplicating any of them.

**Architecture:** A new family directory `home/skills/observability/` following the established family pattern (parent `SKILL.md` with routing table, flat by-concern children, one `platforms/` subdirectory for the one per-platform dimension — mirroring `programming/languages/*.md`). Each file is markdown only; there is no code in this plan (the `sift` CLI it references is a separate plan/package and does not need to exist yet).

**Tech Stack:** Markdown (Claude Code skill format), this repo's Nix/home-manager build (`just build ali-desktop`) as the only mechanical verification available for a docs-only change.

## Global Constraints

- Design source of truth: `docs/superpowers/specs/2026-09-01-observability-skill-design.md`. Every task below implements one section of it; do not deviate from its content plan.
- Skill file frontmatter/description conventions: `skill-authoring/conventions.md` (lead with the verb, cover the broken case, 250–450 characters, negative case stated when confusable with a neighbour).
- Cross-reference, never duplicate: `debugging`'s method, `infra`'s ask-before-mutating rule, `programming/observability.md`'s instrumentation conventions. Any task that finds itself restating one of those has a bug — link instead.
- No hardcoded instance URLs, API keys, or org-specific IDs anywhere (design doc's Non-goals). Generic query/API guidance only.
- No invented `pup` CLI flags. Point at `pup --help`/`pup <subcommand> --help` for the current flag surface — never assert a flag from memory as fact.
- Every task's "test" step is: `just build ali-desktop` succeeds from the repo root, plus a grep-based self-check described in the step (there is no unit-test framework for prose; this is the docs-family equivalent of red/green).
- Commit atomically per task, per this repo's git mandate: one commit per task, `git add` only the files that task touched.
- Work from `/home/ali/git/personal/nix-config` (or the current worktree) — run `git status` before any destructive git command, per this session's safety rules.

---

### Task 1: Create the `observability` skill family skeleton with routing

**Files:**
- Create: `home/skills/observability/SKILL.md`
- Create: `home/skills/observability/investigation.md` (stub — one line, replaced in Task 2)
- Create: `home/skills/observability/improving.md` (stub — one line, replaced in Task 3)
- Create: `home/skills/observability/coverage.md` (stub — one line, replaced in Task 4)
- Create: `home/skills/observability/postmortems.md` (stub — one line, replaced in Task 5)
- Create: `home/skills/observability/platforms/datadog.md` (stub — one line, replaced in Task 6)
- Create: `home/skills/observability/platforms/grafana-lgtm.md` (stub — one line, replaced in Task 7)

**Interfaces:**
- Produces: the routing table other tasks' files are linked from. Tasks 2–7 each replace their stub file's single placeholder line with real content; they do not touch `SKILL.md` again.

Stubs exist so `just build ali-desktop` (which evaluates the whole flake, including every file under `home/skills/`) succeeds after this task even though the child content isn't written yet — an unresolved markdown link target isn't a Nix eval error, but writing real files now (even one-line ones) means every subsequent task's diff is additive-only, never "create," which keeps each task's diff focused on its own content.

- [ ] **Step 1: Write the stub child files**

`home/skills/observability/investigation.md`:
```markdown
# Investigating a live system
```

`home/skills/observability/improving.md`:
```markdown
# Improving observability
```

`home/skills/observability/coverage.md`:
```markdown
# Finding what needs monitoring
```

`home/skills/observability/postmortems.md`:
```markdown
# Postmortems
```

`home/skills/observability/platforms/datadog.md`:
```markdown
# Datadog
```

`home/skills/observability/platforms/grafana-lgtm.md`:
```markdown
# Grafana / LGTM + Prometheus
```

- [ ] **Step 2: Write `SKILL.md`**

```markdown
---
name: observability
description: Use when debugging or investigating a live/production system's performance or reliability through an observability platform (Datadog, Grafana/LGTM — Loki, Tempo, Mimir, or a directly-run Prometheus), including reading dashboards, querying logs/traces/metrics, improving alerting/dashboards/SLOs/cost, auditing a system (a VM or a set of cloud resources) for monitoring coverage gaps, or writing a postmortem after an incident. Not for instrumenting your own code (see the programming skill's observability.md) and not for deploying or mutating infrastructure (see the infra skill).
---

# Observability

This family teaches how to investigate a live system through an
observability platform, how to proactively find what isn't monitored
yet, how to reconstruct and write up an incident afterward, and how to
improve observability itself (close gaps, design better alerts and
dashboards, control cost) as a deliberate activity rather than a side
effect of firefighting.

## What this is not

- **Not instrumenting your own code.** Writing log fields, choosing a
  level, adding a span — that's `programming`'s
  [observability.md](../programming/observability.md). This family is
  the other end of the same loop: an investigation here that hits a
  missing signal hands off to that file to add it.
- **Not deploying or mutating infrastructure.** Creating or editing a
  monitor, dashboard, or alert is a mutation of a live system — `infra`
  owns "ask before mutating live infrastructure"; this family points
  back to it rather than restating the rule.
- **Not the general debugging method.** `debugging` carries reproduce,
  probe the layer closest to the fault, positive control, and distrust
  of a green signal (`debugging/false-signals.md`). This family applies
  that method through a specific platform's tools — it does not
  redefine it.

## By-concern routing

| Doing | Read |
|---|---|
| Investigating a performance or reliability problem on a live system | [investigation.md](investigation.md) |
| Closing an instrumentation gap, designing an alert or dashboard, defining an SLO, or controlling log/metric/trace cost | [improving.md](improving.md) |
| Finding out what isn't monitored yet — auditing a VM/host or a set of cloud resources for coverage gaps before an investigation needs them | [coverage.md](coverage.md) |
| Reconstructing an incident after the fact and writing it up | [postmortems.md](postmortems.md) |

## Platform routing

| Working with | Read |
|---|---|
| Datadog (logs, APM/traces, metrics/dashboards, monitors, the `pup` CLI) | [platforms/datadog.md](platforms/datadog.md) |
| Grafana, Loki, Tempo, Mimir, or a directly-run Prometheus | [platforms/grafana-lgtm.md](platforms/grafana-lgtm.md) |

## Related

- The general debugging method this family applies through a
  platform's tools: the `debugging` skill.
- Asking before mutating a live system — creating or editing a
  monitor, dashboard, or alert: the `infra` skill.
- Writing the instrumentation an investigation finds missing: the
  `programming` skill's [observability.md](../programming/observability.md).
- Reducing a platform's raw output before it reaches Claude's context
  (aggregate/top-N/histogram/diff instead of a raw dump): the `sift`
  CLI, referenced from `investigation.md` and both platform files.
- Paging rotations and live incident comms are out of scope for this
  family — `postmortems.md` starts once the incident is over.
```

- [ ] **Step 3: Verify the build**

Run: `just build ali-desktop`
Expected: succeeds (exit 0), same as any other docs-only change in this
repo — no Nix eval error from the new files.

- [ ] **Step 4: Commit**

```bash
git add home/skills/observability/
git commit -m "feat(observability-skill): add family skeleton with routing"
```

---

### Task 2: Write `investigation.md`

**Files:**
- Modify: `home/skills/observability/investigation.md` (replace the Task 1 stub)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the "reporting a finding" format that `improving.md` (Task 3) references when describing how a closed gap should be written up.

- [ ] **Step 1: Write the file**

```markdown
# Investigating a live system

Applies `debugging`'s method — reproduce, probe the layer closest to
the fault, use a positive control, distrust a signal until you've
checked what it actually means — through an observability platform
instead of a local reproduction. The method doesn't change; what
changes is which query answers which question.

## Symptom-first triage

Start from what's actually reported, not a guessed cause. The symptom
tells you which signal to check first:

- **Latency** (a request, a job, a page load is slow): duration
  histograms and percentiles first (p50 vs p99 tells you "slow for
  everyone" vs "slow for a tail"), then traces for the specific slow
  requests, then the span inside those traces that actually took the
  time.
- **Errors** (a request fails, a job crashes, a health check fails):
  error-rate metrics first (is it a spike or a sustained level?), then
  logs filtered to the error window, then traces for a specific failed
  request if the error is intermittent.
- **Saturation** (a queue backs up, a resource is exhausted, throughput
  drops under load): the RED/USE framing — Rate/Errors/Duration for a
  request-driven service, Utilization/Saturation/Errors for a resource
  (CPU, memory, connection pool, disk) — points at which resource to
  check before diving into logs.

A dashboard or query chosen because it matches the symptom answers a
question directly; one chosen because "it's the dashboard I always
open" produces a tour of the system, not an answer.

## Correlate across signals

A trace ID (or the equivalent request/job correlation ID — the same
concept `programming/observability.md` mandates producers thread
through a unit of work) is the thread that ties one slow or failed
request in a metric dashboard to its specific trace to its specific log
lines. Pull that thread:

1. Find the metric or dashboard panel that shows the symptom.
2. Narrow to a specific instance of it (a specific slow request, a
   specific failed job) — most platforms let you jump from a metric
   spike to the traces or logs that contributed to it.
3. Follow the correlation ID from that specific instance into the
   traces and logs that share it.

Treat logs, traces, and metrics as three views of the same event
stream, not three separate tools to check in sequence and reconcile by
hand. A platform that supports jumping directly from one to another via
a shared ID (Datadog's "related traces/logs" on a span, Grafana
exemplars linking a Prometheus/Mimir metric to a Tempo trace) exists
specifically to save that reconciliation step — use it before falling
back to a manual correlation-ID search.

## Distrust the dashboard

`debugging/false-signals.md` applies directly: a green panel can mean
"healthy" or it can mean "no data reached this query," and those look
identical at a glance. Before trusting a query result:

- Check the query actually matched something. A log search with zero
  results and a log search with a broken filter both show "0" — widen
  the time range or drop a filter to confirm the pipe isn't simply
  empty.
- Check the time range. A dashboard defaulting to "last 15 minutes"
  during an investigation of something that happened two hours ago
  shows a true, useless "nothing's wrong" for the window it's actually
  looking at.
- Check what the metric is actually measuring versus what you assume it
  measures. A "success rate" panel built from a status-code-based
  metric shows 100% right through an outage where the service returns
  200 with an empty or wrong body — the same "clean exit code ≠
  healthy" trap `debugging/false-signals.md` names for local processes.

## Reporting a finding

Mirrors the `review` skill's "phrasing a finding": state what was
checked, what it showed, and what's still unconfirmed, so the
investigation's output is usable by someone who wasn't there watching
you run queries — the same reasoning that makes
observability-driven-development worth doing in the first place applies
to the investigation itself.

    2026-09-01T14:32:00Z: p99 latency on checkout-service jumped from
    120ms to 4.8s at 14:15Z (Datadog dashboard: checkout-latency).
    Traced 6 slow requests in that window; all 6 spend >90% of their
    time in a single span calling inventory-service. inventory-service's
    own error rate is flat, but its p99 latency shows the same jump at
    14:15Z. Not yet confirmed: what changed on inventory-service at
    14:15Z — next step is its deploy history and its own downstream
    calls.

No conclusion presented as fact until it's actually confirmed — "not
yet confirmed" is not a weakness in the report, it's the difference
between an investigation and a guess dressed up as one.

## Reducing what reaches you

A raw query against a real platform can return thousands of lines for
what should be a one-line answer. Reach for the `sift` CLI (see
`platforms/datadog.md` and `platforms/grafana-lgtm.md`) to get an
aggregated, top-N, histogram, or baseline-diff view instead of a raw
dump — the same reduction discipline that makes an investigation's
*output* readable (above) applies to the queries that produced it.
```

- [ ] **Step 2: Verify the build**

Run: `just build ali-desktop`
Expected: succeeds (exit 0).

- [ ] **Step 3: Verify cross-references, not restatement**

Run: `grep -c "reproduce\|probe the layer\|positive control" home/skills/observability/investigation.md`
Expected: 0 — the file references `debugging`'s method by name/link, it
does not restate the method's own definitions. If this greps > 0,
re-read the file for accidental restatement and cut it back to a link.

- [ ] **Step 4: Commit**

```bash
git add home/skills/observability/investigation.md
git commit -m "feat(observability-skill): write investigation.md"
```

---

### Task 3: Write `improving.md`

**Files:**
- Modify: `home/skills/observability/improving.md` (replace the Task 1 stub)

**Interfaces:**
- Consumes: the "reporting a finding" format from Task 2's `investigation.md` (referenced, not restated, in the "closing gaps" section).
- Produces: nothing consumed by later tasks in this plan; `platforms/datadog.md` and `platforms/grafana-lgtm.md` (Tasks 4–5) reference this file's alert-design and cost-control sections rather than restating them.

- [ ] **Step 1: Write the file**

```markdown
# Improving observability

Investigating a live system and improving its observability are the
same skill applied at different times — an investigation that hits a
dead end because a signal doesn't exist *is* the deliverable, not a
failure. This file covers that gap-closing, plus alert design,
dashboard design, SLOs, and cost control as deliberate activities in
their own right.

## Closing gaps found during investigation

When `investigation.md`'s triage hits a dead end — no trace covers the
slow span, no log line exists for the failure path that actually ran,
no metric exists for the resource that saturated — write that down with
the same precision as any other finding (see `investigation.md`'s
"reporting a finding"), then hand it to `programming`'s
[observability.md](../programming/observability.md) as the actual
instrumentation work. This file does not duplicate that file's log
level/field/span conventions — it only says when a gap qualifies as
worth closing: when the *next* investigation of the same kind would hit
the same dead end.

## Alert design

An alert is a claim that a human should act now. Every property below
exists to keep that claim true.

### Avoid flapping

A monitor that fires and clears repeatedly on the same underlying
condition trains its responder to ignore it — the alert becomes noise
before the tenth occurrence.

- **Sustained-condition thresholds.** Require the condition to hold for
  a minimum duration (a "for" / pending period) before firing, so one
  noisy sample above the line doesn't trigger a page for a value that's
  back to normal by the time anyone looks.
- **Hysteresis.** Clear at a different (less strict) threshold than the
  one that triggered the alert — a metric oscillating exactly at a
  single threshold re-fires on every crossing; a gap between trigger
  and clear absorbs that oscillation.
- **Size the evaluation window against the signal's own noise**, not a
  round number picked without looking. A metric with high natural
  variance needs either a longer window or a percentile-based threshold
  (p99 over 5 minutes, not "any single data point") to avoid alerting on
  its own normal spread.

### Exception-based, not surveillance-based

Silence should mean healthy. If a person has to look at a dashboard on
a schedule to notice something is wrong, that's a finding — the fix is
a monitor, not a habit.

- Prefer anomaly, outlier, or forecast detection over a static threshold
  on a signal that's naturally variable across time of day or day of
  week — a static threshold on a signal with a strong daily cycle is
  either always slightly wrong or tuned so loose it never fires.
- Prefer a burn-rate alert (how fast an error budget is being consumed)
  over a raw instantaneous error-rate threshold when an SLO exists —
  see SLOs below.

### Priority routes, not just fires

Severity should map to real urgency and route accordingly: page for
"this needs a human right now," ticket for "this needs attention this
week," silent log for "this is worth knowing happened, not worth
interrupting anyone." One flat severity for everything trains people to
either ignore all alerts or treat every ticket-worthy one as a fire
drill.

### Point at cause, not symptom, wherever the causal chain is knowable

Alert on the most causally-proximate signal available — a specific
dependency's own error rate or queue depth — over a downstream
aggregate ("CPU high," "requests slow") that could have a dozen causes.
Where the platform supports it, use its correlation features (Datadog
related signals, Grafana exemplars linking a metric to a trace) so the
alert itself hands the responder a lead instead of just a fact to go
investigate from scratch. This is "where possible," not a hard
requirement per alert — the causal chain isn't always knowable ahead of
time, and an aggregate symptom alert is still better than no alert.

## Dashboard design

Build a dashboard to answer the question it exists for, not to display
every metric that exists for a service. The RED/USE framing from
`investigation.md`'s symptom-first triage is a reasonable default panel
layout for a single service's dashboard: rate, errors, and duration (or
utilization/saturation/errors for a resource) as the top row, with
anything else below it existing because a specific past investigation
needed it — the same "close the gap you found" discipline as above,
applied to dashboards instead of raw signals.

## SLOs / error budgets

Define an SLO as a measurable, user-facing promise (99.9% of requests
under 500ms, not "the service should be fast") with an explicit
measurement window and error budget. Review existing SLOs against
whether they're still measuring something a user would notice breaking
— an SLO nobody has looked at since it was created is a dashboard panel
nobody reads, the same problem as above. A burn-rate alert (see Alert
design) is the practical link between an SLO existing and an actual
page firing before the budget is exhausted.

## Cost control

Logs, metrics, and traces are billed and stored resources. A bad
default multiplies them silently across every request a service
handles.

### Message templating

Store a stable template ID or enum for a known error/event type plus
its structured detail fields as separate attributes, instead of a fresh
free-text interpolated string per occurrence. The backend indexes the
template once instead of paying to store and index a new string on
every occurrence — the cost-driven reinforcement of
`programming/observability.md`'s "structured fields, not an interpolated
sentence."

### Cardinality discipline

A high-cardinality value — a user ID, a raw URL with path parameters, a
request ID — used as a metric label or a Loki log label explodes the
index behind it. Loki in particular is architecturally built around
low-cardinality labels: high-cardinality detail belongs in the parsed
log body, queried at read time, not in the label set. Prometheus, Mimir,
and Datadog all bill or degrade on tag/label cardinality the same way.

### Sampling

Head-based trace sampling (decide at the start of a trace whether to
keep it) is cheap but can miss the interesting tail; tail-based sampling
(decide after seeing the whole trace, e.g. keep all traces with an
error or over a duration threshold) costs more to run but keeps what
actually matters. For logs, keep 100% of errors and sample the routine
successful ones — the volume driver is almost always the successful
path repeated at request scale, not the errors.

### Retention tiering

Shorter retention for verbose/debug-level data, longer retention for
rolled-up or aggregated data (a daily error-count metric costs far less
to keep for a year than the raw logs it was computed from).

### Log level discipline in production

`programming/observability.md` already covers level semantics for
readability; the same discipline pays for itself in cost — `debug`-level
logging left on in a production hot path is a cost multiplier applied
to every request, not just noise.
```

- [ ] **Step 2: Verify the build**

Run: `just build ali-desktop`
Expected: succeeds (exit 0).

- [ ] **Step 3: Verify no restatement of `programming/observability.md`'s level table**

Run: `grep -c "error.*warn.*info.*debug\|Pick the level by who needs" home/skills/observability/improving.md`
Expected: 0 — confirms the level-semantics table itself wasn't copied in,
only referenced.

- [ ] **Step 4: Commit**

```bash
git add home/skills/observability/improving.md
git commit -m "feat(observability-skill): write improving.md"
```

---

### Task 4: Write `coverage.md`

**Files:**
- Modify: `home/skills/observability/coverage.md` (replace the Task 1 stub)

**Interfaces:**
- Consumes: `investigation.md`'s "reporting a finding" format (Task 2, referenced for how to report a gap) and its "distrust the dashboard" section (Task 2, referenced for the absent-`up`-series caveat).
- Produces: nothing consumed by later tasks in this plan.

- [ ] **Step 1: Write the file**

```markdown
# Finding what needs monitoring

Proactive, not reactive: finding what *should* be monitored before an
investigation ever needs it, across a VM/host or a set of cloud
resources making up a system. Distinct from `improving.md`'s "closing
gaps found during investigation" — that's reactive, triggered by an
investigation that already hit a dead end; this is the audit that finds
the dead end before anyone falls into it.

## Enumerate before you check coverage

You cannot know what's unmonitored without first knowing what exists.
Don't hand-roll resource enumeration — lean on existing inventory
tooling:

- **Host/VM level**: `systemctl list-units` for running services;
  `osquery` (SQL-queryable OS state, including a `systemd_units` table
  and listening sockets) for a scriptable structured inventory beyond
  what `systemctl` alone gives you.
- **Cloud resources**: `terraform state list` (or `terraform show
  -json`) when the system is IaC-managed — the fastest, most accurate
  inventory of what's *supposed* to exist, and ties directly into
  `infra`'s "IaC is the source of truth" principle. CloudQuery or
  Steampipe (SQL-queryable cloud-provider APIs) for a live inventory
  independent of IaC state, useful for catching drift — a resource that
  exists in the cloud but not in Terraform state is itself a finding,
  the observability-adjacent cousin of `infra/kubernetes.md`'s "a
  `kubectl apply` outside GitOps is lost on next reconcile."

## Cross-reference against instrumentation, per platform

- **Datadog** ships real coverage tooling for this already — Software
  Catalog and Universal Service Monitoring surface services with no
  telemetry/SLOs/monitors, Resource Catalog and Cloud Security Posture
  Management do the same for cloud resources. Use these directly before
  reaching for anything else; they only see what Datadog was already
  pointed at, so a resource entirely outside Datadog's reach still
  needs the enumeration step above to be found at all.
- **Grafana/Prometheus** has no packaged equivalent. Cross-reference
  Prometheus's own target list (`/api/v1/targets`) against the
  enumerated resource/service list by hand, and treat an absent `up`
  series for an expected target as a gap in its own right — not just
  "no data," an actual finding (see `investigation.md`'s "distrust the
  dashboard": a target that was never scraped and a target that's
  failing to scrape both show as missing data, so confirm which one
  you're looking at before reporting either as healthy or as down).

## Report gaps the same way as any other finding

Use `investigation.md`'s "reporting a finding" format: what was
enumerated, what coverage was found or missing for each, ranked by what
a gap there would actually cost if it went unnoticed during an
incident — a missing alert on a primary database's connection pool
ranks above a missing dashboard panel for a background batch job.

## Tooling

No existing tool does the full enumerate → cross-reference → report
loop across both cloud resources and host services for both Datadog and
Grafana/Prometheus. `sift audit vm` / `sift audit aws` (see the `sift`
package) is the fast-follow that closes this: reusing existing
enumeration tooling (Terraform state, CloudQuery/Steampipe, osquery)
rather than reinventing inventory, adding only the coverage
cross-reference and gap-report layer described above.
```

- [ ] **Step 2: Verify the build**

Run: `just build ali-desktop`
Expected: succeeds (exit 0).

- [ ] **Step 3: Verify no restatement of `investigation.md`'s reporting format**

Run: `grep -c "Not yet confirmed\|checkout-service jumped" home/skills/observability/coverage.md`
Expected: 0 — confirms the file references the reporting format by name
rather than copying `investigation.md`'s worked example into a second
file.

- [ ] **Step 4: Commit**

```bash
git add home/skills/observability/coverage.md
git commit -m "feat(observability-skill): write coverage.md"
```

---

### Task 5: Write `postmortems.md`

**Files:**
- Modify: `home/skills/observability/postmortems.md` (replace the Task 1 stub)

**Interfaces:**
- Consumes: `investigation.md`'s method and "reporting a finding"/"distrust the dashboard" sections (Task 2, applied retroactively to a whole incident); `improving.md`'s "closing gaps" section (Task 3, referenced for where action items route); `coverage.md`'s framing (Task 4, referenced for the specific case of a missing-monitor action item).
- Produces: nothing consumed by later tasks in this plan.

- [ ] **Step 1: Write the file**

```markdown
# Postmortems

Full postmortem practice: reconstructing what happened, writing it up
blamelessly, and tracking the resulting action items. Paging rotations
and live incident comms stay out of scope — this file starts once the
incident is over and the question becomes "what happened and what do we
do about it."

## Reconstruction is investigation, applied after the fact, for the whole incident

`investigation.md`'s method — symptom-first triage, correlating across
signals, distrusting the dashboard — applies here too, but for the
entire incident window rather than one symptom. Build the full timeline
by pulling the same correlation thread (trace ID → traces → logs)
across the whole window, not just the first anomaly found — an incident
with one root cause commonly has multiple visible symptoms across
different services, and a postmortem that stops at the first one found
produces an incomplete or wrong root cause.

`investigation.md`'s "distrust the dashboard" checks apply retroactively
too: a metric that looked fine during the incident because its query
was scoped wrong or its time range defaulted somewhere unhelpful needs
re-checking with the benefit of hindsight, not trusted just because
nobody caught the problem with it at the time.

## Blameless means explaining what made sense at the time, not who to fault

A postmortem that names an individual as the cause has usually stopped
one level too shallow. "Engineer X pushed a bad config" is an
observation, not a root cause — the root cause is whatever let a bad
config reach production undetected: missing validation, missing staging
parity, missing alert on the exact signal that would have caught it
(which is itself a `coverage.md`-style gap worth naming explicitly in
the postmortem's follow-up items).

## Action items are gap-closing, and they route to the file that owns the gap

A missing instrumentation signal found while reconstructing the
timeline routes to `programming/observability.md` (write the
instrumentation) via `improving.md`'s "closing gaps" section; a missing
alert or monitoring coverage routes to `coverage.md` or `improving.md`'s
alert-design section. The postmortem's job is to *find and route* the
gap, not to re-derive how to fix it — this file does not duplicate
either of those files' content.

## A postmortem with no unresolved action items is a red flag

If reconstructing an incident revealed nothing worth fixing, either the
reconstruction stopped too early or the incident really was pure bad
luck with no systemic contributor — the latter is rare enough that it
deserves stating explicitly rather than silently assumed.
```

- [ ] **Step 2: Verify the build**

Run: `just build ali-desktop`
Expected: succeeds (exit 0).

- [ ] **Step 3: Verify no restatement of `investigation.md`'s method definitions**

Run: `grep -c "reproduce\|probe the layer\|positive control" home/skills/observability/postmortems.md`
Expected: 0 — same check as Task 2 Step 3, applied to this file.

- [ ] **Step 4: Commit**

```bash
git add home/skills/observability/postmortems.md
git commit -m "feat(observability-skill): write postmortems.md"
```

---

### Task 6: Write `platforms/datadog.md`

**Files:**
- Modify: `home/skills/observability/platforms/datadog.md` (replace the Task 1 stub)

**Interfaces:**
- Consumes: `improving.md`'s alert-design principles (Task 3, referenced when describing monitor authoring).
- Produces: nothing consumed by later tasks in this plan.

- [ ] **Step 1: Write the file**

```markdown
# Datadog

Covers logs, APM/traces, metrics/dashboards, and monitors. For the
general investigation method (which signal to check first, how to
correlate, how to distrust a dashboard), see `../investigation.md` —
this file is the Datadog-specific "how," not a second copy of the
"what order."

## Logs

Datadog's log search uses facets (indexed fields) and free-text search
combined. Filter to a facet before free-text searching within it where
possible — a facet filter is indexed, free-text search over the whole
log body is not, and the difference matters at real log volume both for
query speed and for how much you're charged to search it.

A log-based metric (a count or measurement derived from a log query,
tracked over time without re-searching the raw logs) is worth creating
once a specific log search becomes something you check repeatedly —
that's a `improving.md` "close the gap" moment: a search you keep
re-running by hand is a metric you haven't created yet.

## APM / traces

The service map shows the topology as Datadog has observed it operating
— useful for confirming which services a request actually touched, not
just which ones the architecture diagram says it should touch. Trace
search supports filtering by service, operation, tag, and duration; a
flame graph for one specific slow trace is where `../investigation.md`'s
"narrow to a specific instance, then follow it" step lands.

Related logs and related traces (Datadog's own cross-linking from a
span to the logs/traces sharing its trace ID) are the platform's
built-in version of `../investigation.md`'s "pull the correlation-ID
thread" — use them before falling back to a manual trace-ID search
across log/trace search separately.

## Metrics / dashboards

The metrics explorer supports ad hoc queries over any tagged metric;
prefer querying an existing dashboard's saved query (visible via the
dashboard's query inspector) over rebuilding the same query from
scratch, since the existing one has already been tuned for the
right aggregation and rollup.

## Monitors

Reading a monitor's alert history (when it fired, for how long, what
the value was at the time) is the first check before assuming a firing
monitor is wrong — confirm what it actually measured before deciding
it's a false positive. When authoring or tuning a monitor, apply
`../improving.md`'s alert-design section in full: sustained-condition
thresholds and hysteresis against flapping, anomaly/forecast detection
over a static threshold on a variable signal, a severity that routes
correctly, and (where the causal chain is knowable) alerting on the
most proximate signal rather than a downstream aggregate.

Creating or editing a monitor or dashboard is a mutation of a live
system — see the `infra` skill for the ask-before-mutating rule before
doing either.

## The `pup` CLI

`pup` is Datadog's own CLI. Use it for the same investigation patterns
above from a terminal instead of the web UI: searching logs, querying
metrics, and correlating by trace ID. Its exact subcommands and flags
change between versions — run `pup --help` and `pup <subcommand> --help`
to confirm the current surface rather than assuming a remembered flag is
still correct; asserting a flag from memory as fact is exactly the kind
of unverifiable claim this skill avoids.

This repo also ships `claude-dd` — a wrapper that loads the
`pup-claude` plugin (49 agents, ~14 skills purpose-built around `pup`)
on top of the normal `claude` session. Reach for it when a task needs
deep `pup`-specific tooling beyond what this file covers; nothing in
this file or `../investigation.md` depends on it, and both work in a
normal session with `pup` on `PATH`.

## Reducing output before it reaches you

A raw `pup` log search or trace search can return far more than an
investigation needs to answer one question. Reach for `sift datadog
logs`/`sift datadog metrics`/`sift datadog traces` (see the `sift`
package) for an aggregated, top-N, histogram, or baseline-diff view
instead of raw output — `--mode aggregate` to group by facet/error type,
`--mode topn` for the biggest contributors, `--mode histogram` for a
time-bucketed rate, `--mode diff` against a baseline window. `sift`
defaults away from a raw dump; ask for `--mode raw` explicitly when you
actually need every line.
```

- [ ] **Step 2: Verify the build**

Run: `just build ali-desktop`
Expected: succeeds (exit 0).

- [ ] **Step 3: Verify no invented `pup` flags**

Run: `grep -nE "pup [a-z]+ --[a-z]" home/skills/observability/platforms/datadog.md`
Expected: no output — confirms the file never asserts a specific `pup`
flag as fact. If this matches anything, remove the asserted flag and
replace it with the `--help` pointer.

- [ ] **Step 4: Commit**

```bash
git add home/skills/observability/platforms/datadog.md
git commit -m "feat(observability-skill): write platforms/datadog.md"
```

---

### Task 7: Write `platforms/grafana-lgtm.md`

**Files:**
- Modify: `home/skills/observability/platforms/grafana-lgtm.md` (replace the Task 1 stub)

**Interfaces:**
- Consumes: `improving.md`'s cardinality-discipline section (Task 3, restated as a Loki-specific design rule, not duplicated).
- Produces: nothing consumed by later tasks in this plan.

- [ ] **Step 1: Write the file**

```markdown
# Grafana / LGTM + Prometheus

Covers Loki (logs), Grafana (dashboards/API), Tempo (traces), and
Mimir/Prometheus (metrics) — the LGTM stack plus a directly-run
Prometheus, which is common enough in a self-hosted setup to need its
own operational notes even though it shares a query language with
Mimir. For the general investigation method, see `../investigation.md`;
this file is the how, not a second copy of the order.

## Loki (LogQL)

A LogQL query is a label selector (`{app="checkout"}`) piped through
filters and parsers (`|= "error"`, `| json`, `| logfmt`). The label
selector is the expensive/indexed part — keep labels low-cardinality
(service name, environment, not a user ID or request ID) and do
high-cardinality filtering inside the pipe, parsed from the log line
itself at query time. This is `../improving.md`'s cardinality-discipline
section applied specifically to Loki: a high-cardinality label doesn't
just cost more here, it's the one thing Loki's design assumes you won't
do, and doing it anyway degrades every query against that stream.

`count_over_time`, `rate`, and `sum by (...)` turn a raw log stream
query into an aggregate — reach for these before pulling raw lines when
the question is "how many" or "what's the trend," not "show me the
specific lines."

## Grafana (dashboards / API)

The Grafana HTTP API (`/api/dashboards/`, `/api/datasources/`) supports
reading and writing dashboards as JSON. Prefer reading an existing
dashboard's JSON model to understand its query/panel structure before
building a new one from scratch — dashboards-as-code (checking the JSON
into version control) is the mutation-safe way to iterate on one; a
change made only through the UI is the same "not landed in the repo of
record" problem `infra/kubernetes.md` describes for a `kubectl apply`
made outside GitOps. Creating or editing a dashboard, alert rule, or
data source is a mutation — see the `infra` skill for the
ask-before-mutating rule.

## Tempo (TraceQL)

TraceQL queries traces by span attributes (`{ span.http.status_code =
500 }`), similar in spirit to LogQL's label-then-filter shape but over
spans instead of log lines. Grafana's exemplars feature links a
Prometheus/Mimir metric data point directly to the Tempo trace that
contributed to it — the LGTM-stack equivalent of Datadog's related
traces, and `../investigation.md`'s "pull the correlation-ID thread"
step should reach for it before a manual trace-ID search.

## Mimir / Prometheus (PromQL)

Both speak PromQL, but they are operationally distinct:

- **Mimir** is Prometheus-compatible long-term storage, typically fed by
  remote-write from one or more Prometheus instances (or scraped
  directly in an Agent-mode setup). Multi-tenant, built for retention
  beyond what a single Prometheus instance holds locally.
- **A directly-run Prometheus** has its own scrape targets and service
  discovery (who it's pulling metrics from and how it finds them) and
  its own paired **Alertmanager** — Prometheus doesn't have Datadog-style
  "monitors" living in the same product; alerting rules live in
  Prometheus itself and fire to Alertmanager, which handles routing,
  grouping, and silencing. Apply `../improving.md`'s alert-design section
  (sustained-condition thresholds via `for:`, hysteresis, exception-based
  alerting) to Prometheus alerting rules the same way as any other
  platform's monitors.

When a local Prometheus feeds a Mimir instance via remote-write (the
common personal-infrastructure shape), query against Mimir for anything
beyond Prometheus's own local retention window, and against the local
Prometheus directly for anything about scrape health or recent data that
hasn't landed in Mimir's remote-write ingestion path yet.

## Reducing output before it reaches you

A raw LogQL/PromQL/TraceQL query can return far more than an
investigation needs. Reach for `sift lgtm logs`/`sift lgtm
metrics`/`sift lgtm traces` (see the `sift` package) for an aggregated,
top-N, histogram, or baseline-diff view instead of raw output — the
same `--mode` flags as `sift datadog` (aggregate/topn/histogram/diff),
since `sift` shares one reduction engine across both platforms. `sift`
defaults away from a raw dump; ask for `--mode raw` explicitly when you
actually need every line.
```

- [ ] **Step 2: Verify the build**

Run: `just build ali-desktop`
Expected: succeeds (exit 0).

- [ ] **Step 3: Verify no restatement of `improving.md`'s full cardinality section**

Run: `grep -c "billed or degrade on tag" home/skills/observability/platforms/grafana-lgtm.md`
Expected: 0 — confirms the file references cardinality discipline as a
Loki-specific rule without copying `improving.md`'s full paragraph.

- [ ] **Step 4: Commit**

```bash
git add home/skills/observability/platforms/grafana-lgtm.md
git commit -m "feat(observability-skill): write platforms/grafana-lgtm.md"
```

---

### Task 8: Final self-review pass and PR

**Files:** none created or modified — verification only.

**Interfaces:**
- Consumes: every file from Tasks 1–7.
- Produces: nothing; terminal task of this plan.

- [ ] **Step 1: Run the full build one more time from a clean state**

Run: `just build ali-desktop`
Expected: succeeds (exit 0).

- [ ] **Step 2: Confirm every routing table entry resolves**

Run: `for f in investigation.md improving.md coverage.md postmortems.md platforms/datadog.md platforms/grafana-lgtm.md; do test -f "home/skills/observability/$f" && echo "OK: $f" || echo "MISSING: $f"; done`
Expected: six `OK:` lines, no `MISSING:` lines.

- [ ] **Step 3: Confirm the description states the negative case**

Run: `grep -c "Not for instrumenting\|not for deploying" home/skills/observability/SKILL.md`
Expected: >= 1 — confirms the description still disambiguates against
`programming/observability.md` and `infra` per `skill-authoring/conventions.md`.

- [ ] **Step 4: Open the PR**

```bash
git push -u origin docs/observability-skill-implementation
gh pr create --title "feat(observability-skill): add investigation and improvement skill family" --body "$(cat <<'EOF'
## Summary
- Implements docs/superpowers/specs/2026-09-01-observability-skill-design.md's skill-docs half (the sift CLI is a separate plan/PR).
- Adds home/skills/observability/: SKILL.md (routing), investigation.md (platform-agnostic method), improving.md (gap-closing, alert/dashboard design incl. anti-flapping/exception-based/priority-routing/cause-over-symptom, SLOs, cost control), coverage.md (proactive monitoring-gap audits across a VM or cloud resources), postmortems.md (full postmortem practice), platforms/datadog.md, platforms/grafana-lgtm.md (LGTM + Prometheus).
- Cross-references debugging, infra, and programming/observability.md throughout instead of duplicating them.

## Test plan
- [x] just build ali-desktop - evaluates and builds clean
- [x] Routing table entries all resolve to real files
- [ ] just switch - needs to happen on the desktop itself
EOF
)"
```

Note: this task assumes Tasks 1–7 were committed on a branch named
`docs/observability-skill-implementation`, branched from an up-to-date
`main` (`git fetch origin main && git checkout -b
docs/observability-skill-implementation origin/main` before Task 1). If
`main` has moved since that branch point, rebase before pushing (see
this repo's git skill for the rebase-and-force-push-with-lease pattern
used throughout this session).
