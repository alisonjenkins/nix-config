# Testing Go

- `go test ./...` is the bar; table-driven tests (`[]struct{ name string;
  in, want T }` looped with `t.Run(tt.name, ...)`) are the idiomatic shape
  for multiple cases of the same function.
- **`go test -race` in CI for anything with goroutines or shared state.**
  It finds real races that only manifest under specific interleavings — a
  reported race is a bug, not a flaky test. See
  `../../programming/languages/go.md`'s `concurrency.md` for the underlying
  discipline (goroutine ownership, context cancellation, mutex scope).
- `t.Parallel()` for independent subtests once they're race-clean; a test
  that mutates shared package-level state cannot be marked parallel until
  that state is scoped or serialised.
- `t.Cleanup(fn)` over manual `defer` chains in table-driven tests — it
  composes correctly when a subtest adds its own resources.
- Fakes over mocking frameworks: a hand-written struct implementing the
  narrow interface a function accepts (`io.Reader`, a small repository
  interface) beats a generated mock — see this skill's general mocking
  policy.
- `go test -bench=. ./...` (`testing.B`) for benchmarks; keep them in
  `_test.go` files beside the code they measure, not a separate package.
