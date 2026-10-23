---
name: security
description: >-
  Use when asked to check a Nix flake's hosts for vulnerabilities, run vulnix,
  audit a NixOS or home-manager closure, triage CVEs, or patch or bump a
  vulnerable package. Scans the evaluated config, never a live switch.
metadata:
  summary: "Use to scan NixOS/home-manager configs for CVEs with vulnix, triage false positives, and patch."
---

# vuln-scan: vulnix per host, then patch

vulnix matches every derivation in a closure (name + version) against the NVD
CVE feed. **Always scan the runtime closure with `-C`.** Without it vulnix walks
the whole *derivation* closure, build-time tools included (fetchers' `curl`,
bootstrap compilers, `cargo`): on `ali-desktop` that gave 329 hits against 131
for `-C`, and the extra ones are not shipped to the machine.

## 1. Scan

```bash
command -v vulnix || alias vulnix='nix run nixpkgs#vulnix --'   # probe first; not on every machine
host=ali-desktop
out=$(nix build --no-link --print-out-paths ".#nixosConfigurations.$host.config.system.build.toplevel")
vulnix -C --json "$out" > "$SCRATCH/vulnix-$host.json"          # SCRATCH = session scratchpad
vulnix -C "$out"                                                # human summary
```

- `-C` needs a built output path. For the machine you are on, scan
  `/run/current-system` (no build). For another host, build its toplevel; CI's
  binary cache usually substitutes it. Only fall back to a `.drv` path
  (`nix eval --raw ...toplevel.drvPath`, no build, aarch64-safe) when a build is
  impossible, and expect build-tool noise.
- Scan several hosts in parallel as separate calls; they share the NVD cache
  (`~/.cache/vulnix`). First run downloads the feed (minutes); it can fail on NVD
  rate limits, so retry with backoff.
- Home-manager configs: `.#homeConfigurations.<name>.activationPackage.drvPath`.
- vulnix exits non-zero when it finds anything (1 or 2 seen), so do not treat
  that as failure in scripts (`|| true`, or read the JSON).
- Inspect keys before scripting against the JSON: `jq '.[0] | keys'`.
- vulnix lists only the derivation name. Before editing anything, find where a
  hit comes from, because bumping `nixpkgs` does nothing for a package that
  arrives from another input (`unstable`, `master`, `stable`, other flakes have
  their own locks):
  1. Compare the package's version at each input's locked rev:
     `nix eval --raw github:nixos/nixpkgs/<rev>#<pkg>.version` for every
     nixpkgs input in `flake.lock` (`jq -r '.nodes.root.inputs'` lists them; read
     the rev from the node it names, not from a node with the same name). The
     input whose version equals the hit is the source; if none matches, the
     package bundles its own copy.
  2. Trace the consumer against the **built** closure, using a store path that
     is in it (`-lib`, `-bin`, not `-doc`/`-dev`):
     `nix why-depends <toplevel> <path-in-closure>`.
- A lock whose date is months old on a release branch means the channel is end
  of life and frozen: `nix flake update <input>` is a no-op. Check with
  `nix flake update <input>` plus `git diff --stat flake.lock`, then move the
  input to the current release branch.

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

- Verify **every** CVE of a name before whitelisting it, not the top three: a
  package can have a Jenkins-plugin CVE and a real one under the same name.
- vulnix does not order pre-release suffixes: "before 5.42.3-RC1" still matches
  an installed 5.42.3. That is a false positive; say so in the comment.
- "through X" where X is the newest release means no fix exists yet; "before 9.0"
  means only the 9.x line is fixed. Neither is fixed by a bump within the same
  line.
- A summary written by a delegate model is a lead list. On `ali-desktop` Gemini
  Flash got about 80% right, mislabelled a perl false positive as
  "fixed in newer", and called `git` a collision after seeing 3 of its 6 CVEs.
  Check its claims against the full descriptions.

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
   update recipe). Often the whole fix. If it changes nothing, see the EOL
   bullet above.
2. **Take the package from a newer channel** at the place that installs it:
   `pkgs.unstable.<pkg>` or `pkgs.master.<pkg>`. Confirm the newer channel's
   version is past the fixed version first. This cleared 24 `vim` CVEs.
3. **Move an end-of-life input to the current release branch**
   (`nixos-25.11` to `nixos-26.05` cleared 214 CVEs). Afterwards re-test any
   `permittedInsecurePackages` entry for that input; one was no longer needed.
4. **Overlay a patch**: `overrideAttrs` with `fetchpatch` of the upstream fix.
   This is a version override and therefore a pin: if the repo tracks pins
   (e.g. `pins/registry.json` plus a `pins` skill), read that first and register
   it with a reason, deadline and probe.
5. **A library each package bundles itself** (ffmpeg is the case here: kodi,
   lutris, blender, citron, makemkv and zen each carried a different one) and no
   release has the fix: read [bundled-libs.md](bundled-libs.md) before touching
   it. It rebuilds dependents, so measure first.
6. **Remove the package** when it bundles a library whose ABI cannot be replaced
   (kodi needs ffmpeg 6) and the user agrees.
7. **Never** add to `permittedInsecurePackages` to make a CVE go away; that
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
