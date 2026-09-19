---
name: observability
description: Use when investigating a live system's performance or reliability via Datadog or Grafana/LGTM (Loki, Tempo, Mimir, or Prometheus): dashboards, logs/traces/metrics, alert/dashboard/SLO/cost improvements, coverage gaps, or a postmortem. Covers LogQL/PromQL/TraceQL, Alertmanager rules, the `pup` and `sift` CLIs. Not for instrumenting your own code (see programming) or deploying/mutating infrastructure (see infra).
---

# Observability

Investigating a live system through an observability platform, finding
what isn't monitored yet, reconstructing and writing up an incident, and
improving observability itself (closing gaps, alert and dashboard
design, cost control) as deliberate work rather than a side effect of
firefighting.

## What this is not

- **Not instrumenting your own code.** Log fields, levels, spans:
  `programming`'s [observability.md](../programming/observability.md).
  An investigation here that hits a missing signal hands off to that
  file to add it.
- **Not deploying or mutating infrastructure.** Creating or editing a
  monitor, dashboard, or alert mutates a live system; `infra` owns the
  ask-before-mutating rule.
- **Not the general debugging method.** `debugging` carries reproduce,
  probe the closest layer, positive control, and distrust of a green
  signal (`debugging/false-signals.md`). This family applies that
  method through a platform's tools.

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

- Reducing a platform's raw output before it reaches Claude's context
  (aggregate/top-N/histogram/diff instead of a raw dump): the `sift`
  CLI, referenced from `investigation.md` and both platform files.
- Paging rotations and live incident comms are out of scope;
  `postmortems.md` starts once the incident is over.
