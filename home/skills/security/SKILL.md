---
name: security
description: >-
  Use when asked to audit for security vulnerabilities, known CVEs or advisories:
  run vulnix on a Nix flake's hosts, NixOS or home-manager closures, scan the
  packages a repo defines (for example a flake's packages.<system>.* outputs,
  OCI images, Rust crates), cargo audit or cargo deny advisories, RustSec,
  dependency vulnerabilities, generate an SBOM (sbomnix, bombon, Syft, Grype),
  triage a vulnerability report, whitelist or
  ignore false positives, or patch, bump or override a vulnerable package or
  bundled library. Scans and builds only, never a live switch.
metadata:
  summary: "Use to audit CVEs and advisories: vulnix on Nix closures, cargo-deny on Rust repos, packages a repo defines; triage and patch."
---

# Security: find known vulnerabilities, triage, patch

Pick the scanner by what the code is made of. Most repos need two, because each
tool is blind to what the other sees.

| Target | Read |
|---|---|
| NixOS or home-manager host, any built Nix output: vulnix, provenance, whitelist, nixpkgs bumps | [nix-closure.md](nix-closure.md) |
| A library a package bundles itself (ffmpeg and the like), no release has the fix | [bundled-libs.md](bundled-libs.md) |
| Rust crates (`Cargo.lock`, `deny.toml`): cargo-deny, RustSec | [rust.md](rust.md) |
| Packages a repo defines (flake `packages.<system>.*`, OCI images, charts) | [repo-packages.md](repo-packages.md) |
| An SBOM, a second scanner opinion, a dependency graph, SLSA provenance: sbomnix, bombon, Syft, Grype | [sbom.md](sbom.md) |

## Rules that hold for every scanner

- **A scanner reports leads, not verdicts.** Name-and-version matching
  produces false positives (different product, same name; fix backported;
  pre-release suffix). Read the advisory text of every hit before acting.
- **Never silence a hit you have not verified**, and never silence one that has
  no fix: record it in the report. Every ignore needs a reason and a review
  date (`until` in vulnix, a comment plus a tracking issue in `deny.toml`).
- **Say what a scanner cannot see.** vulnix does not see statically linked
  crates; cargo-deny does not see the C libraries nixpkgs supplies. State which
  half was not scanned.
- **Find where a hit comes from before editing.** The fix lives in the input,
  crate or channel that supplies it, not where the scanner printed it.
- **Check the fix exists.** "through X" with X the newest release means no fix.
- A summary from a delegate model is a lead list; check its claims.
- One commit per package fix (invoke the `git` skill first). A version
  override is a pin: register it if the repo tracks pins.

## Boundaries

- Build and scan only. `just switch`, `just deploy` or any activation on live
  hosts is ask-first (see the `infra` skill).
- Scanning is read-only and idempotent; safe to re-run.
- Repo hygiene (branch protection, renovate, CI, secret scanning) is the
  `repo-audit` skill, not this one.
