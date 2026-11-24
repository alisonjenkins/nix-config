# Update policy

Status: accepted (2026-11-20). Implementation is in progress; see [What is implemented](#what-is-implemented).

One policy for every automated update in this repository and in
[home-cluster](https://github.com/alisonjenkins/home-cluster): flake inputs,
Renovate bumps (Cargo, GitHub Actions, container images, Helm charts) and the
Flux controllers. Each repository's configuration implements this file. If the
two disagree, this file is right and the configuration is a bug.

## Goals

1. Security fixes reach every machine quickly, without a human.
2. A poisoned upstream release does not. A release is held back long enough
   for the ecosystem to notice a compromise (LiteLLM 1.107.0, 2026-10-21, was
   live for about 3 hours).
3. Every rule is deterministic and checked in CI. No step depends on an LLM.
4. Anything the automation cannot decide safely becomes a PR or issue with a
   clear reason, never a silent stall.

## Trust tiers

Every source of code belongs to exactly one tier. A source not listed is
**untrusted** until it is added.

| Tier | What | Examples | Cooldown | Auto-merge |
| --- | --- | --- | --- | --- |
| **own** | Your own repositories and registries | `alisonjenkins/*` flakes, `ghcr.io/alisonjenkins/**` | none | yes |
| **core** | Gated by an upstream release process with many reviewers | `nixos/nixpkgs` channels (Hydra-gated), `actions/*`, `github/*`, Docker Official Images | none for a channel bump; 3 days otherwise | yes |
| **established** | Organisations with several maintainers and a track record | `nix-community/*`, `NixOS/*`, `hercules-ci/*`, `numtide/*`, `cachix/*`, `serokell/*`, `lnl7/nix-darwin`, `oxalica/*`, `ipetkov/crane`, `fluxcd/*`, `cilium/*`, `jetstack/*` | 7 days | yes |
| **individual: cosmetic** | One- or two-maintainer projects that only supply data (themes, colour schemes), no code that runs | `tinted-theming/*`, `tomyun/base16-fish`, `rafaelmardojai/firefox-gnome-theme` | 7 days | yes, if the diff passes the review gates below |
| **individual: code** | One- or two-maintainer projects whose code runs on your machines | `danth/stylix` (ships NixOS and home-manager modules), `YaLTeR/niri`, `noctalia-dev/*`, `quickshell-mirror/*`, `pjones/plasma-manager`, `gmodena/nix-flatpak`, `pabloaul/lsfg-vk-flake` | 7 days | **no**: a PR to read, batched weekly |
| **sensitive** | Code that holds credentials, runs as kernel or boot code, or runs agent-controlled code | `xddxdd/nix-cachyos-kernel`, `lanzaboote`, `litellm`, `hermes-agent`, `n8n`, `signal-cli`, and any GitHub Action that receives credentials (see below) | 7 days | **no**: a PR to read |

**Cosmetic** means the input's outputs are only consumed as data: colour
values, theme files, CSS. An input that provides a package, module, overlay
or anything that is executed is **individual: code**, however small. A
cosmetic input whose diff adds Nix code that builds or runs something fails
the review gates and becomes a PR.

**GitHub Actions are sensitive when they get credentials**: a token with any
write permission, a GitHub App token, a secret, cloud credentials (OIDC
`id-token: write` included), or a job on the self-hosted runner. Every other
Action takes its owner's tier (`actions/*` and `github/*` are **core**).

The tier list lives in one machine-readable file, `pins/sources.json`, next
to the pins registry, so both repositories' tooling read the same data. CI
fails when an input, image, chart or action has no tier. A match is
`<kind>:<owner>/<repo>` in lowercase (`github:`, `gitlab:<host>/`, `tarball:`,
`action:`), a `*` segment matches one path segment, and the most specific
match wins, so `github:nix-community/lanzaboote` (sensitive) overrides
`github:nix-community/*` (established).

**Language packages** (npm, crates, PyPI, Go modules) that Renovate bumps take
the **established** tier by default: 7 days, minor and patch auto-merge, majors
by hand. A package can be given a different tier with a Renovate rule that
names it.

## Rules for every update

- **Pin by content, not by name.** Flake inputs are locked by `flake.lock`.
  Images are `tag@sha256:...`. Actions are pinned to a full commit SHA. A
  branch or floating tag (`@main`, `latest`) is not allowed outside the **own**
  tier.
- **Cooldown is measured from upstream publication**, not from when we first
  saw the release. A release whose publication time cannot be established is
  never treated as aged (Renovate `minimumReleaseAgeBehaviour:
  timestamp-required`). It waits for a human.
- **Never take a too-new version when an aged one exists.** If 1.2.4 is two
  hours old and 1.2.3 is ten days old, the update goes to 1.2.3.
- **Majors are never auto-merged**, in any tier except **own**.
- **New sources are never auto-merged.** Adding a flake input, image, chart
  or action, or changing an existing one's owner or URL, needs a human, and
  the PR must add its tier entry.
- **A digest change under an unchanged tag is reviewed by hand** unless the new
  digest carries a valid signature from the publisher's known identity
  (cosign/sigstore keyless, checked against an allowlisted issuer and
  subject). A re-pointed tag otherwise looks exactly like a legitimate rebuild.

## Security fast path

An update that fixes a published advisory (GHSA, OSV, NVD, or a nixpkgs
security backport) skips the cooldown for the **core** and **established**
tiers only. The advisory must name the package and the fixed version. Renovate
does this with `vulnerabilityAlerts` and `osvVulnerabilityAlerts`. For flake
inputs, the CVE scanner (step 3 of the plan) supplies the advisory. Every other
gate still applies.

## Review gates before an auto-merge

An update auto-merges only when all of these pass:

1. **Evaluates and builds.** nix-config: `flake-check`, extended to evaluate
   every host's toplevel. home-cluster: `flux build` of each Kustomization,
   `helm template` of each changed HelmRelease, and `kubeconform` against the
   schemas.
2. **Workflow hygiene.** `actionlint` and `zizmor` pass on any changed
   workflow. No new `permissions:`, secrets, `pull_request_target` or
   self-hosted runner use without a human.
3. **Diff limits for the individual: cosmetic tier.** For a flake input: no new
   `builtins.fetch*` or network fetch at evaluation time, no new
   setuid or systemd units running as root, and no change to `flake.nix`
   inputs of the input itself (its own supply chain). These are deterministic
   checks over the input's diff, not a judgement.
4. **Scan.** No new critical or high CVE introduced, by vulnix (closures) and
   Trivy (images).

## Flake inputs: how the cooldown is applied

`nix flake update` takes the newest commit of every input, so the nightly job
uses `update-policy bump` (in `pkgs/update-policy`) instead. For each direct
input in `flake.lock` it:

1. reads the input's tier from `pins/sources.json`;
2. asks GitHub for the current head of the input's branch or tag with
   `git ls-remote` (no API token, no REST rate limit);
3. records the head in `pins/flake-seen.json` with today's date if it has not
   been seen before;
4. picks the newest recorded commit, newer than the locked one, that was
   first seen at least the tier's cooldown ago (a nixpkgs channel branch such
   as `nixos-unstable` has no cooldown: Hydra already gates it);
5. locks to it with `nix flake lock --override-input`, which keeps the
   `flake.nix` reference as it is.

**The cooldown runs from when we first saw a commit, not from its commit
date.** Anyone can set a commit date, so a poisoned commit backdated by a
month would otherwise skip the wait. The cost is that the first run sees
everything as new: for the first 7 days after this ships, only the `own`
tier and nixpkgs channels move.

Transitive inputs move with the input that brings them in. Inputs pinned to
a `rev` in `flake.nix` are left alone (they are in the pins registry).

The nightly workflow (`update.yaml`) runs `bump --group auto` into the
auto-merged nightly PR, whose body lists what moved, what is waiting and
until when, and what could not be read. On Mondays a second job runs
`bump --group manual` and opens one PR, not auto-merged, for the
**sensitive** and **individual: code** tiers, closing last week's if it is
still open. Only the nightly PR writes `pins/flake-seen.json`, so the two
PRs never conflict over it. `workflow_dispatch` with `manual: true` opens the
review PR on any day. `update-policy bump` with no `--apply` is a dry run.

The nightly job opens its PR, arms auto-merge and exits; it does not wait for
the merge. `update-shepherd.yaml` follows the PR from there, on a
GitHub-hosted runner so it never queues behind the checks it is waiting for.
It runs on every push to main, every finished PR check or nightly run, and
every 30 minutes, and asks `update-policy shepherd` what the open nightly PR
needs:

- **behind main**: rebase it with the updater App token, so its checks run
  again (the App cannot rebase in a main that changed a workflow; that is
  reported instead);
- **a failed check, a conflict, or open 6 hours or more**: open or update one
  issue titled "Nightly flake update is stuck", which says why and links the
  run. It is closed automatically once nothing is stuck. A failed or
  conflicting PR is not retried; the next night's PR supersedes it.

`update-policy shepherd --prs FILE` takes the JSON of `gh pr list --json
number,headRefName,isDraft,createdAt,mergeStateStatus,statusCheckRollup` and
prints the decisions, so a stuck PR can be diagnosed locally.

## What is implemented

| Piece | Where | State |
| --- | --- | --- |
| Tier data | `pins/sources.json` | done: every current flake input and Action |
| `update-policy check` | `pkgs/update-policy` (Rust) | done: runs in the PR check and as a pre-commit hook |
| Renovate rules per tier | `renovate.json` | done (#1015) |
| `update-policy bump` cooldowns | `pkgs/update-policy`, `update.yaml` | done |
| Nightly PR follow-up | `update-policy shepherd`, `update-shepherd.yaml` | done |
| home-cluster checks | home-cluster | planned |

`update-policy check` fails when a flake input (direct or transitive) or a
GitHub Action has no tier, or when an Action outside the `own` tier is not
pinned to a full commit SHA. It warns when an exception is past its
`review_by` date. Each error names the file, the source and the entry to add.
Run it with `just update-policy-check`. Its tests run when the package
builds; `just update-policy-mutants` runs cargo-mutants, and every mutant
should be caught.

## Exceptions

An exception (a longer or shorter cooldown, an auto-merge for something outside
its tier) is an entry in `pins/sources.json` with a reason and a review date,
the same as a pin (ADR 0051). The weekly pins job raises an issue when it
expires.

## What changes against today

| Area | Today | Under this policy |
| --- | --- | --- |
| nix-config Renovate | `:automergeAll`, no cooldown | cooldown by tier, majors and new sources manual |
| nix-config nightly flake update | every input to its newest commit, auto-merged | `update-policy bump` with tier cooldowns; sensitive and individual-code inputs in a weekly review PR |
| home-cluster Renovate | 3 day image/chart cooldown, 7 days for sensitive images, digest bumps manual, Actions manual | unchanged, plus signed digest bumps and core-tier Actions may auto-merge |
| home-cluster PR checks | yamllint only | plus flux build, helm template, kubeconform, actionlint, zizmor |
| home-cluster `flux-upgrade-schedule` | disabled, uses `fluxcd/flux2/action@main` | fixed, pinned by SHA, Flux upgrades through a PR |

## Decisions

- 2026-11-20: single-maintainer inputs are split. Cosmetic ones auto-merge
  after 7 days; ones that run code are always a PR.
- 2026-11-20: the **established** tier waits 7 days, the same as sensitive
  images. Advisory fixes still skip it through the security fast path.
- 2026-11-20: an Action is **sensitive** when it receives credentials or
  runs on the self-hosted runner.
