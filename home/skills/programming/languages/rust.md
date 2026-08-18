# Rust

## Toolchain
- Projects here build with **Nix**: `crate2nix` for the crate graph and
  `dockerTools` for images. Do not add a `Dockerfile`.
- The dev toolchain comes from the flake devshell (`rust-overlay`), never from
  a system-wide `rustup`. `nix develop` before `cargo`.
- `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` are the
  bar; run both before claiming a change is done.

## Idioms
- Errors: `thiserror` for library error enums, `anyhow` only at the binary
  edge. Every `?` boundary that crosses a subsystem gets `.context(...)`.
- No `unwrap()`/`expect()` outside tests and `main`, and when used in `main`,
  the message says what the operator should do about it.
- Prefer borrowed parameters (`&str`, `&[T]`) and return owned types. Clone
  when it makes the lifetime story simple; measure before optimising it away.
- Newtypes over bare `String`/`u64` for identifiers that must not be mixed up.
- `#[derive(Debug)]` on everything that can appear in an error path.

## Async
- One runtime, chosen at the binary. Libraries stay runtime-agnostic.
- Every `spawn` has an owner that awaits or cancels it; no detached tasks that
  outlive the thing they serve.
- Blocking work goes through `spawn_blocking`, never inline in an async fn.

## Traps
- Env-driven configuration is parsed once at startup into a typed struct, not
  read ad hoc at call sites. Wrong-format env values fail loudly at boot.
- Feature flags multiply the build matrix — if you add one, add it to CI.
