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
