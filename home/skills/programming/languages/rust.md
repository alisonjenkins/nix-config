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
opted into. Add a `[lints.clippy]` table to the crate's (or workspace's)
`Cargo.toml`:

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

`[lints.clippy]` needs Cargo 1.74+. On an older toolchain that can't be
upgraded, use the equivalent crate-root attribute instead:

```rust
#![deny(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::unwrap_in_result,
    clippy::panic,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::unreachable,
    clippy::todo,
    clippy::unimplemented,
    clippy::get_unwrap,
)]
```

This makes the existing "no `unwrap()`/`expect()` outside tests and `main`"
rule a lint failure instead of a review-time hope. For the narrow places that
rule already permits — `main`'s top-level error handling, test modules — use
a scoped `#[allow(clippy::unwrap_used)]` on the item, preceded by a `//`
comment saying why, not a blanket crate-level allow — the lint should stay
live everywhere else. (`reason = "..."` inside the attribute itself needs the
nightly-only `lint_reasons` feature; a plain comment above the attribute is
the stable equivalent.) Test
modules commonly get `#![allow(clippy::unwrap_used, clippy::expect_used)]` at
the `#[cfg(test)] mod tests` level, since panicking on bad test setup is the
correct behaviour there.

`indexing_slicing` and `arithmetic_side_effects` will flag plenty of correct
code (a loop indexing within a bound you just checked, a counter that cannot
realistically overflow) — that is the point: replace `v[i]` with
`v.get(i)` and handle the `None` case explicitly (or a scoped `#[allow(...)]`
with a `//` comment above it when a prior check truly makes it unreachable —
see `defensive.md` on assertions vs error handling), and replace
unchecked `+`/`-`/`*` on values from outside this function with
`checked_add`/`saturating_add`/etc. so the panic path is a deliberate, visible
decision at each site rather than an accident of syntax.

## Idioms
- Errors: `thiserror` for library error enums, `anyhow` only at the binary
  edge. Every `?` boundary that crosses a subsystem gets `.context(...)`.
- **One error enum per fallible function, one variant per failure site.** A
  function with three `?`s that can fail three different ways gets an error
  enum with three variants, not one variant wrapping a boxed source. Each
  variant carries the context specific to that site (the path that failed to
  open, the field that failed to parse) so a caller — or a stack trace reader
  months later — can tell which line failed from the variant alone, without
  re-deriving it from a shared message string. Name variants after the
  operation, not the underlying error type (`ConfigRead { path: PathBuf,
  source: io::Error }`, not `Io(io::Error)`), and use `#[from]` only when a
  site is genuinely the sole source of that underlying error type in the
  function — otherwise two call sites collapse into one variant and the
  traceback ambiguity this rule exists to prevent comes right back.
- No `unwrap()`/`expect()` outside tests and `main`, and when used in `main`,
  the message says what the operator should do about it.
- Prefer borrowed parameters (`&str`, `&[T]`) and return owned types. Clone
  when it makes the lifetime story simple; measure before optimising it away.
- **Newtypes over bare `String`/`u64`/`i32` for any identifier or measurement
  that must not be mixed up with another of the same underlying type** —
  `struct CustomerId(String)`, `struct OrderId(String)`, not two `String`
  parameters. `fn f(customer_id: CustomerId, order_id: OrderId)` makes a
  swapped-argument call a compile error instead of a runtime bug. Mandatory
  at any function boundary taking two or more same-typed values that mean
  different things — see `defensive.md`'s "distinct domain concepts" rule.
  A `#[derive(...)]`'d unit struct is zero-cost; there is no runtime reason
  not to.
- `#[derive(Debug)]` on everything that can appear in an error path.
- `tracing`, not `log` or `println!`, for anything beyond a throwaway binary:
  `#[instrument]` on a function turns it into a span with its arguments as
  structured fields for free, and a span nests correctly across an `.await`
  point where a bare log line loses the call stack. Pass fields as
  `tracing::error!(order_id = %order_id, "order failed")` structured key-value
  pairs, not a `format!`'d message. See `../observability.md` for what belongs
  in a log line and at what level.

## Async
- One runtime, chosen at the binary. Libraries stay runtime-agnostic.
- Every `spawn` has an owner that awaits or cancels it; no detached tasks that
  outlive the thing they serve.
- Blocking work goes through `spawn_blocking`, never inline in an async fn.

## Traps
- Env-driven configuration is parsed once at startup into a typed struct, not
  read ad hoc at call sites. Wrong-format env values fail loudly at boot.
- Feature flags multiply the build matrix — if you add one, add it to CI.
