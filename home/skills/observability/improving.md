# Improving observability

Investigating and improving observability are the same skill at
different times: an investigation that dead-ends because a signal
doesn't exist *is* the deliverable, not a failure. This file covers
that gap-closing, plus alert design, dashboard design, SLOs, and cost
control as deliberate work.

## Closing gaps found during investigation

When `investigation.md`'s triage dead-ends (no trace covers the slow
span, no log line for the failure path that ran, no metric for the
resource that saturated), write that down as precisely as any other
finding (`investigation.md`'s "reporting a finding"), then hand it to
`programming`'s [observability.md](../programming/observability.md) as
instrumentation work. That file owns log level/field/span conventions.
This one only says when a gap is worth closing: when the *next*
investigation of the same kind would hit the same dead end.

## Alert design

An alert is a claim that a human should act now. Every property below
exists to keep that claim true.

### Avoid flapping

A monitor that fires and clears repeatedly on the same condition trains
its responder to ignore it; it is noise before the tenth occurrence.

- **Sustained-condition thresholds.** Require the condition to hold for
  a minimum duration (a "for" / pending period) before firing, so one
  noisy sample doesn't page for a value that's normal again by the time
  anyone looks.
- **Hysteresis.** Clear at a less strict threshold than the one that
  triggered. A metric oscillating at a single threshold re-fires on
  every crossing; a gap between trigger and clear absorbs it.
- **Size the evaluation window against the signal's own noise**, not a
  round number. A high-variance metric needs a longer window or a
  percentile threshold (p99 over 5 minutes, not "any single data
  point") or it alerts on its own normal spread.

### Exception-based, not surveillance-based

Silence should mean healthy. If a person has to look at a dashboard on
a schedule to notice something is wrong, that's a finding; the fix is a
monitor, not a habit.

- Prefer anomaly, outlier, or forecast detection over a static threshold
  on a signal that varies by time of day or day of week. A static
  threshold on a strong daily cycle is either always slightly wrong or
  so loose it never fires.
- When an SLO exists, prefer a burn-rate alert (how fast the error
  budget is consumed) over an instantaneous error-rate threshold; see
  SLOs below.

### Priority routes, not just fires

Severity maps to urgency and routes accordingly: page for "a human
now," ticket for "this week," silent log for "worth knowing, not worth
interrupting anyone." One flat severity trains people to ignore all
alerts or treat every ticket as a fire drill.

### Point at cause, not symptom, wherever the causal chain is knowable

Alert on the most causally proximate signal available (a dependency's
own error rate or queue depth) over a downstream aggregate ("CPU high,"
"requests slow") with a dozen possible causes. Where the platform
supports it, use correlation features (Datadog related signals, Grafana
exemplars linking a metric to a trace) so the alert hands the responder
a lead, not just a fact. This is "where possible," not a hard
requirement: the causal chain isn't always knowable ahead of time, and
an aggregate symptom alert beats no alert.

## Dashboard design

Build a dashboard to answer the question it exists for, not to display
every metric a service has. The RED/USE framing from `investigation.md`
is a good default layout for a single service: rate, errors, and
duration (or utilization/saturation/errors for a resource) as the top
row, and anything below it present because a past investigation needed
it, the same "close the gap you found" discipline applied to dashboards.

## SLOs / error budgets

Define an SLO as a measurable, user-facing promise (99.9% of requests
under 500ms, not "the service should be fast") with an explicit window
and error budget. Review existing SLOs for whether they still measure
something a user would notice breaking; an SLO nobody has looked at
since creation is a dashboard panel nobody reads. A burn-rate alert
(see Alert design) is what links an SLO to a page firing before the
budget is exhausted.

## Cost control

Logs, metrics, and traces are billed, stored resources. A bad default
multiplies them silently across every request.

### Message templating

Store a stable template ID or enum for a known error/event type plus
its detail fields as separate attributes, not a fresh interpolated
string per occurrence. The backend indexes the template once instead of
a new string every time: the cost side of
`programming/observability.md`'s "structured fields, not an interpolated
sentence."

### Cardinality discipline

A high-cardinality value (user ID, raw URL with path parameters,
request ID) used as a metric or Loki label explodes the index behind
it. Loki is built around low-cardinality labels: high-cardinality
detail belongs in the parsed log body, queried at read time. Prometheus,
Mimir, and Datadog all bill or degrade on label cardinality the same
way.

### Sampling

Head-based trace sampling (decide at trace start) is cheap but can miss
the interesting tail; tail-based (decide after seeing the whole trace,
e.g. keep every trace with an error or over a duration threshold) costs
more to run but keeps what matters. For logs, keep 100% of errors and
sample the routine successes; the volume driver is almost always the
success path at request scale, not the errors.

### Retention tiering

Shorter retention for verbose/debug data, longer for rolled-up data (a
daily error-count metric costs far less to keep for a year than the raw
logs it came from).

### Log level discipline in production

`programming/observability.md` covers level semantics for readability;
the same discipline pays in cost. `debug` logging left on in a
production hot path multiplies cost on every request, not just noise.
