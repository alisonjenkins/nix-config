---
name: observability
description: Use when investigating a live system's performance or reliability via Datadog or Grafana/LGTM (Loki, Tempo, Mimir, or Prometheus) - dashboards, logs/traces/metrics, alert/dashboard/SLO/cost improvements, auditing a VM or cloud resources for monitoring gaps, or writing a postmortem. Not for instrumenting your own code (see programming's observability.md) or deploying/mutating infrastructure (see infra).
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
