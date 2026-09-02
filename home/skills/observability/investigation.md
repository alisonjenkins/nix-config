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
