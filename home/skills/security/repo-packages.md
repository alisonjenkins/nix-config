# Auditing the packages a repo defines

For a repo that is not a host config but builds software (a flake with
`packages.<system>.*`, an OCI image, a Helm chart: a Rust service packaged
with crane or crate2nix is the typical case). Two views, because each misses what
the other sees:

| View | Finds | Misses |
|---|---|---|
| Lockfile (`cargo deny`, see [rust.md](rust.md); the language's own audit tool otherwise) | Vulnerable crates, modules or npm packages, including statically linked ones | The C libraries and base image the output ships |
| Built output (`vulnix -C`, see [nix-closure.md](nix-closure.md)) | Libraries nixpkgs supplies at runtime: openssl, zlib, ffmpeg, glibc, the image's base layers | Everything linked into the binary |

## Steps

1. **List what the repo builds.**
   `nix flake show --json --all-systems | jq '.packages["x86_64-linux"] | keys'`
   (also `legacyPackages` and `checks`). Pick the shipped outputs: the service
   binary, the OCI image, the UI bundle. Skip test fixtures and compose files.
2. **Scan the lockfile.** `cargo deny check advisories` in the repo root
   ([rust.md](rust.md)). Other ecosystems: use that ecosystem's audit tool
   against its lockfile and note it in the report.
3. **Scan each shipped output at runtime.**
   `out=$(nix build --no-link --print-out-paths .#<package>)` then
   `vulnix -C "$out"`. For an OCI image built by `dockerTools`/`streamLayeredImage`
   the result is a tarball or script, not a closure: scan the package the image
   contains (`.#<service>`), and say the image's base layers were not scanned.
4. **Expect name collisions on Rust output.** Crate names match unrelated NVD
   products. Triage as in [nix-closure.md](nix-closure.md): read every CVE of
   a name before whitelisting, and keep the whitelist file in the repo that
   owns the package.
5. **Helm charts** pin image tags, not CVEs: take the tags from `values.yaml`
   and scan those images, or report them unscanned.
6. **Report per repo and per output**: advisories found, fixed, ignored with
   reason, unscanned halves.

## Patch

Fix in the repo that defines the package, then rebuild it:

- Crate advisories: `cargo update -p <crate>` ([rust.md](rust.md)).
- nixpkgs-supplied library: bump the repo's `nixpkgs` input
  (`nix flake update nixpkgs`), or override at the consumer
  ([nix-closure.md](nix-closure.md), step 3).
- A repo that consumes this one (a host config importing its package) needs
  its own input bump afterwards: `nix flake update <input>` there, and rescan.

One commit per fix; open the PR in the repo that owns the code.
