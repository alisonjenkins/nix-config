---
name: vuln-scan
description: >-
  Use when asked to check a Nix flake's hosts for vulnerabilities, run vulnix,
  audit a NixOS or home-manager closure, triage CVEs, or patch or bump a
  vulnerable package. Scans the evaluated config, never a live switch.
metadata:
  summary: "Use to scan NixOS/home-manager configs for CVEs with vulnix, triage false positives, and patch."
---

# vuln-scan: vulnix per host, then patch

vulnix matches every derivation in a closure (name + version) against the NVD
CVE feed. Scan the **evaluated config**, not the running system: it is
reproducible, needs no build, and works for hosts you are not sitting at.

## 1. Scan

```bash
command -v vulnix || alias vulnix='nix run nixpkgs#vulnix --'   # probe first; not on every machine
host=ali-desktop
drv=$(nix eval --raw ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath")
vulnix --json "$drv" > "$SCRATCH/vulnix-$host.json"             # SCRATCH = session scratchpad
vulnix "$drv"                                                   # human summary
```

- `.drv` scan needs no build; `-S` scans only the *current* machine's
  `/run/current-system`. Use `-S` only for "what is running here now".
- Scan several hosts in parallel as separate calls; they share the NVD cache
  (`~/.cache/vulnix`). First run downloads the feed (minutes); it can fail on NVD
  rate limits, so retry with backoff.
- Home-manager configs: `.#homeConfigurations.<name>.activationPackage.drvPath`.
- aarch64 hosts evaluate fine from x86 for `drvPath`; do not build them to scan.
- vulnix exits 1 when it finds anything, so do not treat that as failure in
  scripts (`|| true`, or read the JSON).
- Inspect keys before scripting against the JSON: `jq '.[0] | keys'`.

## 2. Triage

Rank by CVSS v3 score, then by exposure: network-facing server daemons
(`openssh`, `nginx`, `k3s`, `tailscale`) before desktop-only libs. For each hit
decide one of:

| Verdict | Test | Action |
|---|---|---|
| Fixed upstream in a newer nixpkgs | `nix eval nixpkgs#<pkg>.version` on `unstable`/`master` is past the fixed version | bump (step 3) |
| False positive | nixpkgs backported the fix (patch name contains the CVE id) or the CVE is for a different product with the same name (a Haskell `Diff` matches Drupal's `Diff`; common for Haskell, Perl and Python libs; check the `description` field) | whitelist with reason |
| Not reachable | package in closure but not exercised | whitelist with reason + expiry |
| No fix exists | NVD lists no fixed version | record in report; do not silence |

vulnix does not see backported patches, so false positives are common. Verify a
claimed false positive: `nix build nixpkgs#<pkg>.patches` or grep the derivation
for the CVE id. Never whitelist unverified.

Whitelist file: `security/vulnix-whitelist.toml` in the flake repo (create on first use), passed
with `-w`. Each entry needs `cve`, a `comment` saying why, and `until` (ISO date,
at most 90 days out) so it is re-reviewed:

```toml
["openssl-3.0.13"]
cve = ["CVE-2024-0000"]
comment = "backported in nixpkgs patch openssl-cve-2024-0000.patch"
until = "2027-01-20"
```

## 3. Patch (cheapest first)

1. **Update the input** and rescan: `nix flake update nixpkgs` (or the repo's
   update recipe). Often the whole fix.
2. **Take the package from a newer channel** via the overlay: `pkgs.unstable.<pkg>`
   or `pkgs.master.<pkg>` in the module that installs it.
3. **Overlay a patch**: `overrideAttrs` with `fetchpatch` of the upstream fix.
   This is a version override and therefore a pin: if the repo tracks pins
   (e.g. `pins/registry.json` plus a `pins` skill), read that first and register
   it with a reason, deadline and probe.
4. **Never** add to `permittedInsecurePackages` to make a CVE go away; that
   silences nix, not the vulnerability, and is itself a pin.

One commit per package fix (atomic; invoke the `git` skill before committing).

## 4. Verify

1. Rescan the host: the CVE must be gone, or whitelisted with a comment.
2. `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --no-link`
   (or the repo's build recipe): proves the bump still evaluates and builds.
3. Report per host: CVEs found, fixed, whitelisted (with reason), unfixable.

## Boundaries

- Build and scan only. `just switch`, `just deploy`, or any activation on live
  hosts is ask-first (see the `infra` and `deploy` skills).
- Scanning is read-only and idempotent; safe to re-run.
- Not a substitute for runtime checks: vulnix only knows packages nix tracks.
