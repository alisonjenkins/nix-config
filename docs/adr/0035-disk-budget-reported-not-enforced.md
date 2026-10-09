# 0035. Report the observability stack's disk budget instead of enforcing it

- Status: Accepted
- Date: 2026-10-09

## Context

The stack keeps 30 days of data under a 20 GB disk budget (spec 007, SC-014).
Prometheus can cap itself by size. Loki and Tempo only expire data by age.
The owner prefers more disk use to lost telemetry.

## Decision

A guard runs every five minutes and sums the three data directories. It writes
`guard.json` (`ok` or `over`, bytes used, budget, time). It goes `over` at
`maxDiskGB` and back to `ok` below 90% of it. It never stops a container.

Four channels report `over`: the `observability.guard.over_budget` metric, the
stack-health dashboard, a session-start notice from `cc-obs-ledger notice`, and a
desktop notification (`notify-send` or `osascript`) on the switch to `over` and
at most once per 24 hours after.

Prometheus keeps `--storage.tsdb.retention.size`. It discards its oldest blocks.

## Alternatives rejected

- **Halt the collector.** Loses new data, which is the data we are paying to collect.
- **Filesystem quotas.** Not portable across macOS and the Linux filesystems in use.
- **Deleting Loki or Tempo blocks ourselves.** Risks corrupting the stores.

## Consequences

The budget is not a bound. Disk use can pass it until the owner raises
`maxDiskGB`, cuts collection or shortens retention. A locked or headless
desktop may miss the notification; the other channels still report.

## Evidence

- `nix build .#checks.x86_64-linux.observability-stack-guard`

## Revisit when

The budget is exceeded routinely for a month.
