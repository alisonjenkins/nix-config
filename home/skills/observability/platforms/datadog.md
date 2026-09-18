# Datadog

Covers logs, APM/traces, metrics/dashboards, and monitors. The
investigation method (which signal first, how to correlate, how to
distrust a dashboard) is `../investigation.md`; this file is the
Datadog-specific how.

## Logs

Log search combines facets (indexed fields) and free text. Filter to a
facet before free-text searching within it: a facet filter is indexed,
the log body is not, and at real volume that difference decides both
query speed and search cost.

Create a log-based metric (a count or measurement derived from a log
query, tracked without re-searching raw logs) once a search becomes
something you check repeatedly. That is an `../improving.md` "close the
gap" moment: a search you keep re-running by hand is a metric you
haven't created yet.

## APM / traces

The service map shows the topology as observed, which confirms which
services a request actually touched rather than which the architecture
diagram says. Trace search filters by service, operation, tag, and
duration; the flame graph for one slow trace is where
`../investigation.md`'s "narrow to a specific instance, then follow it"
lands.

Related logs and related traces (cross-links from a span to the
logs/traces sharing its trace ID) are the built-in version of
`../investigation.md`'s "pull the correlation-ID thread"; use them
before a manual trace-ID search.

## Metrics / dashboards

The metrics explorer runs ad hoc queries over any tagged metric. Prefer
an existing dashboard's saved query (via its query inspector) over
rebuilding it; the existing one is already tuned for aggregation and
rollup.

## Monitors

Read a monitor's alert history (when it fired, for how long, the value
at the time) before assuming it's wrong; confirm what it measured
before calling it a false positive. When authoring or tuning one, apply
`../improving.md`'s alert-design section in full: sustained-condition
thresholds and hysteresis, anomaly/forecast detection over a static
threshold on a variable signal, severity that routes correctly, and
(where the causal chain is knowable) the most proximate signal over a
downstream aggregate.

Creating or editing a monitor or dashboard mutates a live system; see
`infra` for the ask-before-mutating rule.

## The `pup` CLI

`pup` is Datadog's CLI: the same patterns above from a terminal,
searching logs, querying metrics, correlating by trace ID. Subcommands
and flags change between versions; run `pup --help` and
`pup <subcommand> --help` rather than trusting a remembered flag. A
flag asserted from memory is the unverifiable claim this skill avoids.

## Reducing output before it reaches you

A raw `pup` log or trace search returns far more than one question
needs. Use `sift datadog logs`/`sift datadog metrics`/
`sift datadog traces` (the `sift` package) instead: `--mode aggregate`
groups by facet/error type, `--mode topn` shows the biggest contributors,
`--mode histogram` gives a time-bucketed rate, `--mode diff` compares
against a baseline window. `sift` defaults away from a raw dump; pass
`--mode raw` when you need every line.
