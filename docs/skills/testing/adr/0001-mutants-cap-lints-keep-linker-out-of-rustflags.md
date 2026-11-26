# 0001. Choose the linker with `linker`, not rustflags, when cargo-mutants caps lints

- Status: Accepted
- Date: 2026-11-26

## Context

A Rust repo picked lld through `.cargo/config.toml`:

```toml
[target.x86_64-unknown-linux-gnu]
rustflags = ["-C", "link-arg=-fuse-ld=lld"]
```

Its `mutants.toml` set `cap_lints = true`, so mutants that leave unused code
behind are not rejected by `#![deny(warnings)]`. Under `cargo mutants` the
links used far more memory than a normal build.

The cause is in cargo-mutants and Cargo together:

- With `cap_lints` on, cargo-mutants sets `CARGO_ENCODED_RUSTFLAGS` for
  every build (`src/cargo.rs`, `encoded_rustflags`). It starts from the
  `CARGO_ENCODED_RUSTFLAGS` or `RUSTFLAGS` environment variable and appends
  `--cap-lints=warn`. Its own comment says it "does not currently read
  config files". The book's limitations page says flags set in
  `.cargo/config.toml` "will be ignored".
- Cargo's rustflags sources are mutually exclusive. The first one present
  wins: `CARGO_ENCODED_RUSTFLAGS`, then `RUSTFLAGS`, then
  `target.<triple>.rustflags` / `target.<cfg>.rustflags`, then
  `build.rustflags`.

So `-fuse-ld=lld` never reaches rustc, nothing warns, and the link falls back
to the C compiler's default linker. On a GNU toolchain that is `ld.bfd`.
With `cap_lints` off, cargo-mutants sets nothing and the config flags apply.

The `linker` key is separate from rustflags. Cargo reads it from config even
when `CARGO_ENCODED_RUSTFLAGS` is set.

## Decision

In `home/skills/testing/languages/rust.md`, under the cargo-mutants section:
when `cap_lints` is on, move the linker choice out of rustflags into a
committed wrapper script named by `target.<triple>.linker`. Give the
`debug.log` and `readelf -p .comment` checks to detect the problem. Keep any
other required flags in `RUSTFLAGS` for the run.

The rule is written for any repo, not one project: it names the mechanism,
not the repo where it was found.

## Alternatives rejected

- **Turn `cap_lints` off.** Brings the config flags back, but mutants that
  trip `deny(warnings)` become unviable, which is why the option was on.
  Fine for a repo without strict lints; not a general fix.
- **Set `RUSTFLAGS` with the lld flags for the run.** Works, since
  cargo-mutants appends to it. But it must repeat every config rustflag, for
  every target, and drift from the config. cargo-mutants also splits it on
  spaces, so quoted arguments break. Kept as the fallback for flags that are
  not a linker choice.
- **Gate strict lints behind a `cfg` feature instead.** The book's other
  option. Valid, but a bigger change to the repo than the linker wrapper.

## Consequences

- The repo carries a small wrapper script, and it must be committed:
  cargo-mutants copies the tree to a scratch directory, and the relative
  `linker` path must resolve there.
- The wrapper is per target triple. macOS and Windows targets need their own
  linker setting.
- Rust 1.90+ defaults to a bundled `rust-lld` on `x86_64-unknown-linux-gnu`,
  but distro builds (nixpkgs rustc 1.95.0 among them) may not. Check with
  `readelf`; do not assume.

## Evidence

- cargo-mutants source at 6c720ae (27.1.0), `src/cargo.rs`
  `encoded_rustflags`; book `limitations.md` and `lints.md`
  (<https://mutants.rs/lints.html>).
- Cargo config reference, `build.rustflags`:
  <https://doc.rust-lang.org/cargo/reference/config.html#buildrustflags>.
- Reproduced 2026-11-26 with cargo-mutants 27.1.0, rustc 1.95.0 (nixpkgs),
  lld 21.1.8, on a toy crate with the config above and `cap_lints = true`:
  - `mutants.out/debug.log`: `encoded_rustflags="--cap-lints=warn"`.
  - A test binary from `cargo test`: `Linker: LLD 21.1.8` in
    `readelf -p .comment`. The binary rebuilt by `cargo mutants --in-place`:
    no LLD line.
  - With `linker = "tools/cc-lld"` (`exec "${CC:-cc}" -fuse-ld=lld "$@"`)
    and no rustflags, `--in-place` binaries show `Linker: LLD 21.1.8`, and
    the default copy-to-scratch run passes.

## Revisit when

- cargo-mutants reads Cargo config rustflags, or passes `--cap-lints`
  another way (for example `cargo rustc` or `--config`).
- Cargo merges rustflags sources instead of taking the first.
