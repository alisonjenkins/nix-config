# Investigating a live system

Applies `debugging`'s method (reproduce, probe the layer closest to the
fault, use a positive control, distrust a signal until you've checked
what it means) through an observability platform instead of a local
reproduction. The method doesn't change; which query answers which
question does.

## Symptom-first triage

Start from the reported symptom, not a guessed cause. It tells you
which signal to check first:

- **Latency** (a request, a job, a page load is slow): duration
  histograms and percentiles first (p50 vs p99 separates "slow for
  everyone" from "slow for a tail"), then traces for the slow requests,
  then the span inside them that took the time.
- **Errors** (a request fails, a job crashes, a health check fails):
  error-rate metrics first (is it a spike or a sustained level?), then
  logs filtered to the error window, then traces for a specific failed
  request if the error is intermittent.
- **Saturation** (a queue backs up, a resource is exhausted, throughput
  drops under load): the RED/USE framing (Rate/Errors/Duration for a
  request-driven service, Utilization/Saturation/Errors for a resource:
  CPU, memory, connection pool, disk) points at which resource to check
  before logs.

A query chosen to match the symptom answers a question; "the dashboard
I always open" produces a tour of the system.

## Correlate across signals

A trace ID (or the request/job correlation ID
`programming/observability.md` mandates producers thread through a
unit of work) ties one slow or failed request in a metric dashboard to
its trace and its log lines. Pull that thread:

1. Find the metric or dashboard panel that shows the symptom.
2. Narrow to one instance (a specific slow request or failed job); most
   platforms let you jump from a metric spike to the traces or logs
   behind it.
3. Follow its correlation ID into the traces and logs that share it.

Treat logs, traces, and metrics as three views of one event stream, not
three tools to check in sequence and reconcile by hand. Platform
cross-links (Datadog's "related traces/logs" on a span, Grafana
exemplars linking a Prometheus/Mimir metric to a Tempo trace) exist to
save that reconciliation; use them before a manual correlation-ID
search.

## Distrust the dashboard

`debugging/false-signals.md` applies directly: a green panel can mean
"healthy" or "no data reached this query," and the two look identical.
Before trusting a result:

- Check the query matched something. Zero results and a broken filter
  both show "0"; widen the time range or drop a filter to confirm the
  pipe isn't empty.
- Check the time range. A dashboard defaulting to "last 15 minutes"
  while you investigate something from two hours ago shows a true,
  useless "nothing's wrong" for its window.
- Check what the metric measures versus what you assume. A "success
  rate" panel built on status codes shows 100% through an outage where
  the service returns 200 with an empty or wrong body: the "clean exit
  code ≠ healthy" trap `debugging/false-signals.md` names for local
  processes.

## Reporting a finding

Mirrors the `review` skill's "phrasing a finding": what was checked,
what it showed, what's still unconfirmed, so someone who didn't watch
you run queries can use the output. The reasoning behind
observability-driven development applies to the investigation itself.

    2026-09-01T14:32:00Z: p99 latency on checkout-service jumped from
    120ms to 4.8s at 14:15Z (Datadog dashboard: checkout-latency).
    Traced 6 slow requests in that window; all 6 spend >90% of their
    time in a single span calling inventory-service. inventory-service's
    own error rate is flat, but its p99 latency shows the same jump at
    14:15Z. Not yet confirmed: what changed on inventory-service at
    14:15Z — next step is its deploy history and its own downstream
    calls.

No conclusion presented as fact until confirmed. "Not yet confirmed" is
not a weakness; it's the difference between an investigation and a
dressed-up guess.

## Reducing what reaches you

A raw query can return thousands of lines for a one-line answer. Use
the `sift` CLI (see `platforms/datadog.md` and
`platforms/grafana-lgtm.md`) for an aggregated, top-N, histogram, or
baseline-diff view instead of a raw dump. The discipline that makes the
*output* readable (above) applies to the queries behind it.
