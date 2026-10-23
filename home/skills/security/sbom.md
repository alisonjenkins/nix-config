# SBOMs and sbomnix-style tools

An SBOM lists every component of a build with name, version and identifiers
(CPE, PURL). Scanners then match it against vulnerability feeds. Use one when
the question is "what is in this", when a second scanner opinion is wanted, or
when compliance needs a document. For a plain "which CVEs are in this host",
`vulnix -C` ([nix-closure.md](nix-closure.md)) is faster.

## sbomnix

[sbomnix](https://github.com/tiiuae/sbomnix) (tiiuae, from the Ghaf project) is a
suite of CLI tools for Nix. Run it without installing:

```bash
nix run github:tiiuae/sbomnix#sbomnix -- --help     # also: nixgraph, vulnxscan, nix_outdated, provenance
```

| Tool | Use |
|---|---|
| `sbomnix` | SBOM (CycloneDX `sbom.cdx.json`, SPDX 2.3 `sbom.spdx.json`, `sbom.csv`) from a flake ref, derivation or store path |
| `vulnxscan` | Scans the SBOM; aggregates vulnix, Grype and OSV results, so a hit is cross-checked across three sources |
| `nixgraph` | Dependency graph; answers "why is this in the closure" (like `nix why-depends`) |
| `nix_outdated` | Outdated dependencies, ranked by how many packages depend on each: a bump priority list |
| `provenance` | SLSA v1.0 provenance attestation (JSON) for a flake or derivation |

```bash
sbomnix <flake-path-or-ref>#nixosConfigurations.<host>.config.system.build.toplevel --buildtime
sbomnix <flake-ref>#<pkg>                                           # runtime SBOM; builds the target
sbomnix <flake-ref>#<pkg> --buildtime                               # includes build-time deps, no build
nixgraph <flake-ref>#<pkg> --depth=2
```

- **Prefer a flake reference.** nixpkgs metadata (licence, exact CPE) enriches
  the SBOM only then. A store path or `result` symlink gets almost no CPEs, so
  `vulnxscan` finds less.
- The two `--buildtime` forms were run (a local flake's host toplevel and
  `nixpkgs#hello`); the runtime form was not. Each wrote `sbom.cdx.json`,
  `sbom.spdx.json` and `sbom.csv` into the current directory.
- **Runtime analysis forces a build**; `--buildtime` avoids that but includes
  build-only tools, with the same noise as a `.drv` vulnix scan.
- CPE matching falls back to heuristics: expect false positives and negatives,
  and triage them as in [nix-closure.md](nix-closure.md). `--exclude-cpe-matching`
  turns the heuristics off.
- `vulnxscan` flags are not all documented in the README; read `--help`
  before scripting against its output.

## Alternatives

| Tool | Does | Pick it when |
|---|---|---|
| bombon | CycloneDX SBOM as a Nix function inside the build | the SBOM is a build artefact or compliance requires it (BSI TR-03183, US EO 14028); cannot see vendored Rust or Go deps natively |
| genealogos | CycloneDX SBOM | rarely; smallest and slowest-moving |
| Syft + Grype | General SBOM plus scanner, not Nix-aware | scanning a container image or non-Nix tree, or a non-Nix second opinion |
| FlakeBOM | CycloneDX 1.5 from flakes | only with a Determinate Secure Packages subscription (closed) |
| flakevuln | Daily flake vulnerability scans, GitHub Action or CLI | scheduled scanning in CI instead of by hand |

Activity and claims were checked on 2026-10-24 from the projects' GitHub
pages and READMEs; re-check before recommending one for a long-lived setup.

## Reading an SBOM scan

An SBOM scan is a lead list, like any other scanner output (see the rules in
[SKILL.md](SKILL.md)). Vulnerabilities in vendored Rust, Go or npm
dependencies show up only if the SBOM tool can see them; confirm with the
language's own audit ([rust.md](rust.md)) before declaring a repo clean.
