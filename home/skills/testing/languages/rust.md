# Testing Rust

## Layout
- Unit tests in a `#[cfg(test)] mod tests` beside the code; integration tests
  in `tests/` exercising only the public API.
- `cargo nextest run` when available (better isolation and output), otherwise
  `cargo test`. Doc-tests still need `cargo test --doc`.

## Practice
- Table-driven cases with `rstest` or a plain array of `(input, expected)`
  beats copy-pasted test functions.
- Async tests: `#[tokio::test]`. Give every test that awaits a network or
  channel a timeout so a hang fails instead of stalling CI.
- For client/server crates, spin up the real server on an ephemeral port
  (`:0`), read back the bound address, and drive it with the real client.
- `assert_eq!` on whole structs, not field by field — the diff is the message.
- Property tests (`proptest`) for parsers, encoders, and anything with a
  round-trip law.

## Validate the tests: `cargo-mutants`
Green tests prove nothing until they can go red. Run `cargo mutants` on the
code you changed (`--in-diff <patch>` or `-f <file>`) to validate them: it
rewrites functions (return defaults, flip operators) and re-runs the suite.
A *missed* mutant is a test gap: add an assertion that kills it, or justify
the survivor (`#[mutants::skip]` with a reason; needs the `mutants` crate as a
dependency). Only a clean run supports
"tests cover this". See `../property-based.md` (saboteurs) for the manual form.

### `cap_lints` silently drops config rustflags: lld/mold ignored, links use far more memory (decision testing/0001)
`cap_lints = true` in `mutants.toml` (or `--cap-lints=true`) makes
cargo-mutants set `CARGO_ENCODED_RUSTFLAGS`. Cargo uses only the first
rustflags source it finds, so every `rustflags` in `.cargo/config.toml` is
silently dropped. A linker choice such as `-C link-arg=-fuse-ld=lld` (or
mold) falls back to the default linker, usually `ld.bfd`: slower, and far
more memory per link, times `--jobs`.
- **Detect:** `grep encoded_rustflags mutants.out/debug.log` shows only
  `--cap-lints=warn`. Or a test binary built during the run lacks `Linker:
  LLD` in `readelf -p .comment`.
- **Fix:** choose the linker with `linker`, which is not a rustflag. Commit a
  wrapper that execs the driver the config already uses (`cc`, or `clang` if
  `linker = "clang"`) plus the `-fuse-ld=` that was in rustflags, e.g.
  `tools/cc-lld` containing `exec "${CC:-cc}" -fuse-ld=lld "$@"`, and set
  `[target.<triple>] linker = "tools/cc-lld"` (relative to the directory
  holding `.cargo/`). Other flags you must keep go in `RUSTFLAGS` for the run;
  cargo-mutants appends to it, splitting on spaces.

## Traps
- Tests that share a global (env vars, static state, a fixed port) fail only
  under parallelism. Scope the state or serialise those tests explicitly.
- `#[should_panic]` without `expected = "..."` passes on the wrong panic.
