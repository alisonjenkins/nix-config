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
