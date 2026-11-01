# Documenting infrastructure

## Generate or write

| What | Generate or hand-write | Tool |
|---|---|---|
| Terraform inputs, outputs, providers | generate | terraform-docs in inject mode ("Partially replace the output-file content with generated output") between BEGIN_TF_DOCS and END_TF_DOCS markers in the module README |
| Helm chart values | generate | helm-docs from "# --" comments in values.yaml |
| Intent, trade-offs, upgrade notes | hand-write | module README prose |
| Architecture | hand-write, diagram as source | see [readme-visuals.md](readme-visuals.md) |
| Runbooks | hand-write | docs/runbooks/ |
| Decisions | hand-write | ADRs (see [structure.md](structure.md)) |
| Nix options | generate if the project exposes modules | pkgs.nixosOptionsDoc in nixpkgs (defined in pkgs/top-level/all-packages.nix, implemented in nixos/lib/make-options-doc; lib does not have it; pass options from an evaluation; reference is the source doc comment) |

## Enforce generated docs

Prevent documentation drift using automated checks. With tflint and the bundled terraform ruleset, terraform_documented_variables ("Disallow variable declarations without description.") and terraform_documented_outputs ("Disallow output declarations without description.") both fire with no preset (as notices, exit code 2), so the default behaves like preset = "all"; with preset = "recommended" neither fires, so they are not in the recommended preset.

Use terraform-docs with `--output-mode inject --output-check` as the CI drift gate: an up-to-date README prints "README.md is up to date" and exits 0; when out of date it prints "Error: README.md is out of date" and exits 1. For helm-docs, there is no check or fail-on-diff flag; `-x` / `--documentation-strict-mode` fails generation if there are undocumented values, not on drift. For drift detection, `--dry-run` prints generated documentation to stdout and exits 0 even when the README on disk is stale, so a drift gate must diff the `--dry-run` output against the committed README (or run the pre-commit hook and fail on a dirty tree).

## Module README shape

Structure each module README to guide the reader quickly:
- State what the module is for.
- Provide a minimal usage example.
- Include inputs and outputs (generated).
- List requirements and provider versions.
- Document upgrade notes and breaking changes.
- Note known limits.

Put the example before the generated tables so consumers see usage immediately.

## Runbooks

Create one runbook per alert or recurring task. Suggested sections (the author's own synthesis, as no authoritative template exists in the SRE Workbook incident-response chapter or PagerDuty docs): trigger, impact, first checks, steps with the exact commands, rollback, escalation, owner, last verified date.

Link the runbook from the alert: runbook_url is a convention carried by kubernetes-mixin, not a spec (Prometheus and Alertmanager do not define it, and Prometheus docs only say annotations can hold "runbook links"; kubernetes-mixin lib/add-runbook-links.libsonnet sets runbook_url on alerts that lack it, from runbookURLPattern; kube-prometheus hosts alert runbooks at https://runbooks.prometheus-operator.dev/). Make commands copy-pasteable and idempotent where possible.

Drill rollback and disaster recovery regularly: "Prove that data recovery works with regular exercise, or data recovery won't work." (Google SRE book, Data Integrity chapter).

## Postmortems

Run blameless postmortems after incidents ("Blameless postmortems are a tenet of SRE culture."). Record timeline, impact, root cause, what worked, and action items with owners.

Link the postmortem from the ADR or runbook it changes to keep operational knowledge connected. Source: Google SRE book postmortem-culture chapter.

## Live systems and secrets

Document where a thing runs, never secret values; link to the secret store path. Treat the repo as the source of truth for intended state and say what to check when live state differs.

Infrastructure changes that need a human go through the infrastructure-as-code repo first (judgement, convention).

## Anti-patterns

| Pattern | Fix |
|---|---|
| Hand-written tables of inputs and outputs | Generate them |
| Runbook that lives only in a wiki | Keep it in the repo next to the code |
| Runbook never exercised | Drill it |
| Secrets pasted into docs | Reference the secret path |
| Diagram only as an exported image | Commit the source |

## Sources and confidence

| Source | URL |
|---|---|
| terraform-docs | https://terraform-docs.io/ |
| terraform-docs output configuration | https://terraform-docs.io/user-guide/configuration/output/ |
| helm-docs README | https://github.com/norwoodj/helm-docs/blob/master/README.md |
| tflint rules | https://github.com/terraform-linters/tflint-ruleset-terraform/tree/main/docs/rules |
| Google SRE book postmortem culture | https://sre.google/sre-book/postmortem-culture/ |
| Google SRE book data integrity | https://sre.google/sre-book/data-integrity/ |
| Prometheus alerting rules | https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/ |
| kube-prometheus runbooks | https://runbooks.prometheus-operator.dev/ |
| nixpkgs make-options-doc | https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/make-options-doc/default.nix |
| NixOS manual | https://nixos.org/manual/nixos/stable/ |
| kubernetes-mixin | https://github.com/kubernetes-monitoring/kubernetes-mixin |

Confidence: checked by running the tool or reading source on 2026-10-28. Remaining unverified: runbook sections (author's synthesis); a CI recipe using helm-docs --dry-run was not run end to end.
