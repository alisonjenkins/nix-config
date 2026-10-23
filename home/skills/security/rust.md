# Rust crates: cargo-deny and RustSec

Crates are linked into the binary, so vulnix on the built output never sees
them (a runtime closure holds the executable, not its dependencies). Scan
`Cargo.lock` against the RustSec advisory database instead.

## Scan

```bash
cd <repo>                                   # a workspace root with Cargo.lock
command -v cargo-deny || nix run nixpkgs#cargo-deny -- --version   # probe; not on every machine
cargo deny check advisories                 # human report, honours deny.toml
cargo deny --format json check advisories 2>&1 \
  | jq -r 'select(.type=="diagnostic") | select(.fields.severity=="error")
           | "\(.fields.advisory.id // "-") \(.fields.advisory.package // "-") :: \(.fields.message)"' | sort -u
```

- Use the repo's own `deny.toml`; it carries the advisories already triaged. If
  there is none, `cargo deny init` writes a template.
- The first run fetches the advisory DB from GitHub; it needs network.
- Exit code is non-zero on any error-severity advisory. Do not read that as a
  scanner failure.
- `cargo audit` reads the same database; use it only when `cargo-deny` is
  unavailable.
- Run it per repo, not per host: each repo has its own lock.

## Triage

- Severities differ: a vulnerability is an error, "unmaintained" and
  "unsound" advisories are warnings by default. Report both, fix vulnerabilities
  first.
- Find who pulls the crate: `cargo tree -i <crate>@<version>`. A crate that
  only a proc-macro or a disabled feature reaches (a `sqlx-mysql` that is
  never enabled) is not in the shipped binary, but cargo-deny still lists it
  because it is in the lock.
- A hit is fixed by a patched release: `cargo update -p <crate>` moves within
  the semver range. If the patched version is outside the range, bump the
  requirement in the `Cargo.toml` that owns it, or bump the parent crate that
  pins it.
- `ignore = ["RUSTSEC-..."]` in `deny.toml` only with a comment that states why
  the code path is unreachable, and an issue or date to revisit. An ignore that
  no longer matches prints `advisory-not-detected`: remove it.

## Patch

1. `cargo update -p <crate>` (or `cargo update` for all), then rerun the scan.
2. Rebuild through the repo's own recipe so the lock change is proven to
   build: `nix build .#<package>` or `cargo build --locked`. crane builds read
   `Cargo.lock` directly. crate2nix repos also keep a generated `Cargo.nix`:
   regenerate it with the repo's recipe in the same commit, or the Nix build
   keeps the old crates.
3. Run the repo's tests; a crypto or TLS bump can change behaviour.
4. One commit per crate bump, or one `cargo update` commit if the repo's
   history already groups them (invoke the `git` skill).

## Seen

On 2026-10-24, `cargo deny check advisories` on two repos using the same crate
stack found `rustls`, `rustls-webpki`, `webpki-roots` and `zip` advisories in
both: all linked statically and invisible to vulnix.
