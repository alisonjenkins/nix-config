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

## Traps
- Tests that share a global (env vars, static state, a fixed port) fail only
  under parallelism. Scope the state or serialise those tests explicitly.
- `#[should_panic]` without `expected = "..."` passes on the wrong panic.
