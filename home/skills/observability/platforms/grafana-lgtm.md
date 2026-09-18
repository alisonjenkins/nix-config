# Grafana / LGTM + Prometheus

Covers Loki (logs), Grafana (dashboards/API), Tempo (traces), and
Mimir/Prometheus (metrics): the LGTM stack plus a directly-run
Prometheus, common enough self-hosted to need its own notes despite
sharing a query language with Mimir. The investigation method is
`../investigation.md`; this file is the how.

## Loki (LogQL)

A LogQL query is a label selector (`{app="checkout"}`) piped through
filters and parsers (`|= "error"`, `| json`, `| logfmt`). The label
selector is the indexed part: keep labels low-cardinality (service
name, environment, not user or request ID) and do high-cardinality
filtering inside the pipe, parsed from the line at query time. This is
`../improving.md`'s cardinality discipline applied to Loki: a
high-cardinality label doesn't just cost more, it's the one thing
Loki's design assumes you won't do, and it degrades every query against
that stream.

`count_over_time`, `rate`, and `sum by (...)` turn a stream query into
an aggregate; use them before pulling raw lines when the question is
"how many" or "what's the trend," not "show me the lines."

## Grafana (dashboards / API)

The Grafana HTTP API (`/api/dashboards/`, `/api/datasources/`) reads
and writes dashboards as JSON. Read an existing dashboard's JSON model
before building a new one. Dashboards-as-code (JSON in version control)
is the mutation-safe way to iterate; a UI-only change is the "not
landed in the repo of record" problem `infra/kubernetes.md` describes
for a `kubectl apply` outside GitOps. Creating or editing a dashboard,
alert rule, or data source is a mutation; see `infra` for the
ask-before-mutating rule.

## Tempo (TraceQL)

TraceQL queries traces by span attributes (`{ span.http.status_code =
500 }`), LogQL's label-then-filter shape over spans instead of lines.
Grafana exemplars link a Prometheus/Mimir data point to the Tempo trace
behind it: the LGTM equivalent of Datadog's related traces, and what
`../investigation.md`'s "pull the correlation-ID thread" step should
reach for before a manual trace-ID search.

## Mimir / Prometheus (PromQL)

Both speak PromQL but are operationally distinct:

- **Mimir** is Prometheus-compatible long-term storage, typically fed by
  remote-write from one or more Prometheus instances (or scraped
  directly in Agent mode). Multi-tenant, built for retention beyond a
  single Prometheus.
- **A directly-run Prometheus** has its own scrape targets and service
  discovery (who it pulls from and how it finds them) and a paired
  **Alertmanager**. There are no Datadog-style "monitors" in-product:
  alerting rules live in Prometheus and fire to Alertmanager, which
  routes, groups, and silences. Apply `../improving.md`'s alert-design
  section (sustained-condition thresholds via `for:`, hysteresis,
  exception-based alerting) to Prometheus rules as to any other
  platform's monitors.

When a local Prometheus feeds Mimir via remote-write (the common
personal-infra shape), query Mimir for anything beyond Prometheus's
local retention, and the local Prometheus for scrape health or recent
data not yet ingested by Mimir.

## Reducing output before it reaches you

A raw LogQL/PromQL/TraceQL query returns far more than an investigation
needs. Use `sift lgtm logs`/`sift lgtm metrics`/`sift lgtm traces` (the
`sift` package) for an aggregated, top-N, histogram, or baseline-diff
view; the `--mode` flags match `sift datadog`
(aggregate/topn/histogram/diff) since both share one reduction engine.
`sift` defaults away from a raw dump; pass `--mode raw` when you need
every line.
