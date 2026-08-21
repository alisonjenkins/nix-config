# Rust

## Toolchain
- Projects here build with **Nix**: `crate2nix` for the crate graph and
  `dockerTools` for images. Do not add a `Dockerfile`.
- The dev toolchain comes from the flake devshell (`rust-overlay`), never from
  a system-wide `rustup`. `nix develop` before `cargo`.
- `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` are the
  bar; run both before claiming a change is done.

## Guard rails (mandatory)

Deny the clippy `restriction`-group lints that catch panic-class bugs —
`-D warnings` alone does not enable these; they are off by default and must be
opted into. Add to the crate's (or workspace's) `Cargo.toml`:

```toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "deny"
unwrap_in_result = "deny"
panic = "deny"
indexing_slicing = "deny"
arithmetic_side_effects = "deny"
unreachable = "deny"
todo = "deny"
unimplemented = "deny"
get_unwrap = "deny"
```

This makes the existing "no `unwrap()`/`expect()` outside tests and `main`"
rule a lint failure instead of a review-time hope. For the narrow places that
rule already permits — `main`'s top-level error handling, test modules — use
a scoped `#[allow(clippy::unwrap_used, reason = "...")]` on the item, not a
blanket crate-level allow; the lint should stay live everywhere else. Test
modules commonly get `#![allow(clippy::unwrap_used, clippy::expect_used)]` at
the `#[cfg(test)] mod tests` level, since panicking on bad test setup is the
correct behaviour there.

`indexing_slicing` and `arithmetic_side_effects` will flag plenty of correct
code (a loop indexing within a bound you just checked, a counter that cannot
realistically overflow) — that is the point: replace `v[i]` with
`v.get(i)` and handle the `None` case explicitly (or a scoped
`#[allow(..., reason = "...")]` when a prior check truly makes it
unreachable — see `defensive.md` on assertions vs error handling), and replace
unchecked `+`/`-`/`*` on values from outside this function with
`checked_add`/`saturating_add`/etc. so the panic path is a deliberate, visible
decision at each site rather than an accident of syntax.

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
