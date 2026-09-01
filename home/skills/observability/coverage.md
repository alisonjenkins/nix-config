# Finding what needs monitoring

Proactive, not reactive: finding what *should* be monitored before an
investigation ever needs it, across a VM/host or a set of cloud
resources making up a system. Distinct from `improving.md`'s "closing
gaps found during investigation" — that's reactive, triggered by an
investigation that already hit a dead end; this is the audit that finds
the dead end before anyone falls into it.

## Enumerate before you check coverage

You cannot know what's unmonitored without first knowing what exists.
Don't hand-roll resource enumeration — lean on existing inventory
tooling:

- **Host/VM level**: `systemctl list-units` for running services;
  `osquery` (SQL-queryable OS state, including a `systemd_units` table
  and listening sockets) for a scriptable structured inventory beyond
  what `systemctl` alone gives you.
- **Cloud resources**: `terraform state list` (or `terraform show
  -json`) when the system is IaC-managed — the fastest, most accurate
  inventory of what's *supposed* to exist, and ties directly into
  `infra`'s "IaC is the source of truth" principle. CloudQuery or
  Steampipe (SQL-queryable cloud-provider APIs) for a live inventory
  independent of IaC state, useful for catching drift — a resource that
  exists in the cloud but not in Terraform state is itself a finding,
  the observability-adjacent cousin of `infra/kubernetes.md`'s "a
  `kubectl apply` outside GitOps is lost on next reconcile."

## Cross-reference against instrumentation, per platform

- **Datadog** ships real coverage tooling for this already — Software
  Catalog and Universal Service Monitoring surface services with no
  telemetry/SLOs/monitors, Resource Catalog and Cloud Security Posture
  Management do the same for cloud resources. Use these directly before
  reaching for anything else; they only see what Datadog was already
  pointed at, so a resource entirely outside Datadog's reach still
  needs the enumeration step above to be found at all.
- **Grafana/Prometheus** has no packaged equivalent. Cross-reference
  Prometheus's own target list (`/api/v1/targets`) against the
  enumerated resource/service list by hand, and treat an absent `up`
  series for an expected target as a gap in its own right — not just
  "no data," an actual finding (see `investigation.md`'s "distrust the
  dashboard": a target that was never scraped and a target that's
  failing to scrape both show as missing data, so confirm which one
  you're looking at before reporting either as healthy or as down).

## Report gaps the same way as any other finding

Use `investigation.md`'s "reporting a finding" format: what was
enumerated, what coverage was found or missing for each, ranked by what
a gap there would actually cost if it went unnoticed during an
incident — a missing alert on a primary database's connection pool
ranks above a missing dashboard panel for a background batch job.

## Tooling

No existing tool does the full enumerate → cross-reference → report
loop across both cloud resources and host services for both Datadog and
Grafana/Prometheus. `sift audit vm` / `sift audit aws` (see the `sift`
package) is the fast-follow that closes this: reusing existing
enumeration tooling (Terraform state, CloudQuery/Steampipe, osquery)
rather than reinventing inventory, adding only the coverage
cross-reference and gap-report layer described above.
