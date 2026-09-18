# Finding what needs monitoring

Finding what *should* be monitored before an investigation needs it,
across a VM/host or the cloud resources making up a system.
`improving.md`'s "closing gaps found during investigation" is reactive;
this audit finds the dead end before anyone hits it.

## Enumerate before you check coverage

You cannot know what's unmonitored without knowing what exists. Don't
hand-roll enumeration; use existing inventory tooling:

- **Host/VM level**: `systemctl list-units` for running services;
  `osquery` (SQL-queryable OS state, including a `systemd_units` table
  and listening sockets) for a scriptable inventory beyond `systemctl`.
- **Cloud resources**: `terraform state list` (or `terraform show
  -json`) when the system is IaC-managed: the fastest, most accurate
  inventory of what's *supposed* to exist, and `infra`'s "IaC is the
  source of truth" principle. CloudQuery or Steampipe (SQL-queryable
  cloud-provider APIs) for a live inventory independent of IaC state,
  which catches drift: a resource in the cloud but not in Terraform
  state is itself a finding, the cousin of `infra/kubernetes.md`'s "a
  `kubectl apply` outside GitOps is lost on next reconcile."

## Cross-reference against instrumentation, per platform

- **Datadog** ships coverage tooling: Software Catalog and Universal
  Service Monitoring surface services with no telemetry/SLOs/monitors;
  Resource Catalog and Cloud Security Posture Management do the same
  for cloud resources. Use these first. They only see what Datadog was
  already pointed at, so a resource outside Datadog's reach still needs
  the enumeration step above.
- **Grafana/Prometheus** has no packaged equivalent. Cross-reference
  Prometheus's target list (`/api/v1/targets`) against the enumerated
  list by hand, and treat an absent `up` series for an expected target
  as a finding, not just "no data." Per `investigation.md`'s "distrust
  the dashboard": a never-scraped target and a failing-to-scrape target
  both show as missing data, so confirm which before reporting either
  as healthy or down.

## Report gaps the same way as any other finding

Use `investigation.md`'s "reporting a finding" format: what was
enumerated, what coverage each has or lacks, ranked by what the gap
would cost during an incident. A missing alert on a primary database's
connection pool ranks above a missing dashboard panel for a batch job.

## Tooling

`sift audit vm|aws` will run the enumerate → cross-reference → report
loop automatically once it exists (`pkgs/sift` has no `audit`
subcommand yet; check before assuming). Until then, do the three steps
by hand.
