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
