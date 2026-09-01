# Go

## Toolchain
- `go build ./...`, `go vet ./...`, and `gofmt -l .` (or `goimports -l .`)
  clean are the bar. `go vet` catches a real class of bugs (`Printf` format
  mismatches, lock-copying, unreachable code) that `gofmt` does not.
- `golangci-lint run` if the project has it configured — it aggregates
  `staticcheck`, `errcheck`, `gosec`, and others behind one command; prefer
  running that over remembering which individual linters the project uses.
- Module-aware (`go.mod`) by default; do not vendor unless the project
  already does. `go mod tidy` after adding or removing an import, not as a
  separate untracked step.

## Guard rails (mandatory)
- `errcheck` (via `golangci-lint`, or standalone) enabled and clean. Go's
  compiler does not force you to check an error return — nothing stops
  `f()` silently discarding the `error` `f()` returned — so this is the
  language's equivalent of Rust's `unwrap_used` deny: a lint turning a
  silently-ignorable failure into a build-time one. Never `_ = f()` to
  silence it; handle or explicitly propagate the error instead.
- `go vet -race` (or `go test -race`) in CI for anything with goroutines or
  shared state. The race detector finds real races that only manifest under
  specific interleavings — treat a race it reports as a bug, not a flaky
  test, and see `concurrency.md`.
- `gosec` (or the security rules in `golangci-lint`) for anything handling
  untrusted input, file paths, or subprocess arguments — see `security.md`.

## Idioms
- **Wrap errors with `fmt.Errorf("doing X: %w", err)` at every boundary a
  caller needs to distinguish**, never `fmt.Errorf("doing X: %v", err)` —
  `%v` stringifies and discards the original error, breaking
  `errors.Is`/`errors.As` for every caller above that point. Every wrap
  names the specific operation that failed (`"reading config %s: %w",
  path, err`), so a log line traces back to one call site the same way
  `rust.md`'s per-site error variants do — Go's mechanism is a wrapped,
  named string instead of an enum variant, but the goal is identical:
  never a bare `err` re-returned with no added context.
- **Define a typed/sentinel error for any failure a caller needs to branch
  on**, not a string a caller has to substring-match: `var ErrNotFound =
  errors.New("not found")` or a custom struct implementing `error` (with
  `Unwrap() error` so it composes with `%w`), matched via
  `errors.Is`/`errors.As`, never `strings.Contains(err.Error(), "...")`.
- Return `(T, error)`, not a zero value silently standing in for failure.
  A `nil, nil` return (both zero-valued) from a function whose contract
  says one implies the other is a common defect; keep the two orthogonal.
- Accept interfaces, return concrete structs — a function's parameter
  should ask for the minimal interface it needs (`io.Reader`, not `*os.File`),
  and its return type should be the concrete type callers can act on
  without a type assertion.
- **Named types over bare `string`/`int` for identifiers that must not be
  mixed up** — `type CustomerID string`, `type OrderID string`, not two
  bare `string` parameters. `func f(customerID CustomerID, orderID
  OrderID)` makes a swapped call a compile error. Zero runtime cost; see
  `defensive.md`'s "distinct domain concepts" rule.
- `context.Context` is the first parameter of any function that can block,
  call out to another service, or needs a deadline/cancellation — never
  stored in a struct field, never `context.TODO()` outside a genuine
  stopgap during a migration.
- `log/slog` (stdlib since Go 1.21) for structured logging, not `fmt.Printf`
  or unstructured `log.Println` — `slog.Error("order failed", "order_id",
  orderID, "err", err)` fields, not an interpolated string. See
  `../observability.md`.
- `go test -bench` (with `testing.B`) for benchmarking, `pprof`
  (`go tool pprof`, or `net/http/pprof` for a running service) for
  profiling. See `../performance.md` before reaching for either.

## Concurrency
- Every goroutine has an owner that can observe when it's done and
  propagate its error: `sync.WaitGroup` for fire-and-collect,
  `golang.org/x/sync/errgroup` when any goroutine's error should cancel the
  others. A `go func() { ... }()` with no channel, `WaitGroup`, or context
  tied to it is a leak or a silently swallowed panic waiting to happen —
  this is Go's form of `rust.md`'s "every spawn has an owner" rule.
- A goroutine that can run indefinitely takes a `context.Context` and
  selects on `ctx.Done()`, so cancelling the context actually stops it.
- Protect shared state with a `sync.Mutex`/`sync.RWMutex` held for the
  shortest scope that needs it, or prefer passing ownership through a
  channel over sharing memory at all ("share memory by communicating").
  See `concurrency.md` for the general discipline.

## Traps
- **`defer` in a loop accumulates** — a `defer f.Close()` inside a loop over
  many files holds every file open until the *function* returns, not the
  loop iteration. Wrap the loop body in its own function, or close
  explicitly.
- **Loop variable capture**: pre-Go-1.22, a closure or goroutine launched
  inside a `for _, v := range items` captured the same `v` across every
  iteration, not a fresh copy per item — always a bug in a `go func(){
  use(v) }()` inside a range loop on older toolchains. Go 1.22+ fixed this
  at the language level; know which the project targets before assuming
  either behaviour.
- A `nil` interface holding a typed `nil` pointer is not itself `nil` —
  `var err error = (*MyError)(nil); err != nil` is `true`. Return the bare
  `nil` literal for the no-error case, never a typed nil through an
  `error`-typed return.
- Struct copies: passing a struct with an embedded `sync.Mutex` by value
  copies the lock, silently breaking mutual exclusion. `go vet` catches
  this — see Guard rails.
