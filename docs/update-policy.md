# Update policy

Status: draft for review (2026-11-20).

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

The tier list lives in one machine-readable file, `pins/sources.json`
(proposed), next to the pins registry, so both repositories' tooling read the
same data. CI fails when an input, image, chart or action has no tier.

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
cannot apply a cooldown on its own. The proposed replacement is a small Rust
tool, `flake-bump`, that for each input:

1. reads its tier from `pins/sources.json`,
2. picks the newest upstream commit at least as old as the tier's cooldown
   (for `nixos/nixpkgs`, the current channel head),
3. locks to it with `nix flake lock --override-input`,
4. writes a summary of what moved, what was held back and why, for the PR
   body.

The nightly workflow keeps its current shape (branch, PR, `flake-check`,
auto-merge) and calls `flake-bump` instead of `nix flake update`. Inputs in the
**sensitive** and **individual: code** tiers are bumped in a separate PR that is not auto-merged.

## Exceptions

An exception (a longer or shorter cooldown, an auto-merge for something outside
its tier) is an entry in `pins/sources.json` with a reason and a review date,
the same as a pin (ADR 0051). The weekly pins job raises an issue when it
expires.

## What changes against today

| Area | Today | Under this policy |
| --- | --- | --- |
| nix-config Renovate | `:automergeAll`, no cooldown | cooldown by tier, majors and new sources manual |
| nix-config nightly flake update | every input to its newest commit, auto-merged | `flake-bump` with tier cooldowns; sensitive inputs in a separate PR |
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
