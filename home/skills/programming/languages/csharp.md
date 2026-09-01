# C# / .NET

Covers both **.NET Framework** (4.x, Windows-only, `msbuild`/`packages.config`
or old-style `.csproj`) and **.NET (Core)** (5+, cross-platform, SDK-style
`.csproj`, `dotnet` CLI). Most guidance applies to both; where it does not,
say which.

## Toolchain
- **.NET (Core)**: `dotnet build`, `dotnet test`, `dotnet publish` via the
  SDK-style `.csproj`. `dotnet format --verify-no-changes` for formatting,
  the project's configured analyzers for lint.
- **.NET Framework**: built via `msbuild` (Visual Studio or the standalone
  build tools), package references usually still `PackageReference`-style in
  a modern `.csproj` even on Framework, but an older codebase may use
  `packages.config` — check which before assuming `dotnet restore` alone
  covers it.
- Check the project's `<TargetFramework>` and `<LangVersion>` in its
  `.csproj` before assuming a newer language feature (nullable reference
  types, records, `required` members, top-level statements) is available —
  these are compiler/LangVersion features, not strictly Core-only, and can
  work on Framework with a modern SDK and an explicit `<LangVersion>`
  override, but a Framework project is commonly still pinned to an older
  language version even when the installed SDK supports newer syntax.
  `dotnet --version`/`msbuild -version` only reports the installed
  SDK/MSBuild version, not what the project itself targets — checking that
  tells you nothing about which language features this project can use.

## Guard rails (mandatory)
- **`<Nullable>enable</Nullable>`** in every `.csproj` that can have it
  (Core, and Framework projects on a modern-enough SDK/LangVersion). This is
  the C# equivalent of `rust.md`'s clippy deny list and `typescript.md`'s
  `noUncheckedIndexedAccess`: without it, a `string` and a `string?` are the
  same type to the compiler, so a null falls through to a `NullReferenceException`
  at the access site instead of a compile error at the point it was
  introduced. A project that can't yet go fully nullable-enabled should
  enable it and use `#nullable disable` only on the files that still need
  triage, not skip it project-wide.
- **`<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`** (or the specific
  analyzer rule IDs that matter) — an enabled-but-not-enforced analyzer is
  advisory and gets ignored under deadline pressure; see `defensive.md`'s
  "Guard rails" principle.
- `dotnet test` (or the project's test runner) with code coverage wired into
  CI where the project already tracks it; do not introduce a new coverage
  gate as a drive-by part of an unrelated change.

## Idioms
- **Exceptions are for the exceptional**, not for expected control flow.
  A lookup that can reasonably fail (parse a value, find an entry) uses
  `TryParse`/`TryGetValue`-style methods or returns a nullable/`Result`-style
  type; reserve `throw` for a genuine contract violation or an unrecoverable
  state — see `defensive.md`'s assertions-vs-error-handling table, which
  maps directly onto "exception for a bug" vs "`Try*`/nullable for
  something that can happen."
- **`throw;` to rethrow, never `throw ex;`.** `throw ex;` resets the stack
  trace to the rethrow site, destroying the information that would have
  identified where the exception actually originated — this is the single
  most common C# defect in a `catch` block and it is silent until you need
  the trace and it is gone.
- **Catch the specific exception type.** A bare `catch (Exception)` needs a
  comment saying why the broad catch is correct, and must either rethrow
  (`throw;`) or log with the full exception, not swallow it. An empty
  `catch { }` is never acceptable outside a documented, deliberate
  best-effort cleanup path.
- `using`/`await using` for anything `IDisposable`/`IAsyncDisposable` —
  this is C#'s form of `defensive.md`'s "finish what you start." A `Dispose`
  called manually at the end of a long method is skipped by the first early
  return or exception; `using` is not.
- Records (`record`/`record struct`) for immutable domain data; `init`-only
  properties over public mutable setters when the type represents a value
  rather than an entity with a lifecycle. C# 9+/10+ language features, so
  usable on Framework too with a modern SDK and `<LangVersion>` set high
  enough — see the Toolchain note above.
- **Distinct types for identifiers that must not be mixed up**, even
  without a language-native newtype: a `readonly record struct
  CustomerId(Guid Value)` (see the Toolchain note on LangVersion for
  Framework) or a small `readonly struct` wrapper (either runtime) so
  `void F(CustomerId customerId, OrderId orderId)` rejects a swapped call at
  compile time — plain `Guid`/`Guid` would not. See `defensive.md`'s
  "distinct domain concepts" rule.
- `CultureInfo.InvariantCulture` for any string comparison, parse, or
  formatting that is not user-facing display text — `ToUpper()`/`ToLower()`/
  `string.Compare` under the current culture silently produce different
  results on a machine with a different locale (the classic "Turkish I"
  bug: `"i".ToUpper()` is not always `"I"`).

## Async
- **Never `async void`** except an event handler, where the framework
  requires it. An `async void` method's exceptions cannot be `await`ed or
  caught by the caller — they crash the process (or are silently lost,
  depending on the host) instead of propagating.
- **Never `.Result` or `.Wait()` on a Task from synchronous code** — on
  .NET Framework (and any code still capturing a `SynchronizationContext`,
  e.g. classic ASP.NET or WinForms/WPF UI threads) this is the canonical
  async deadlock: the continuation cannot resume on the captured context
  because that thread is blocked waiting for the continuation. `async` all
  the way up the call stack instead.
- `ConfigureAwait(false)` on every `await` inside library code (not
  application/UI entry points) that does not need to resume on the
  original context — mandatory on .NET Framework libraries for the deadlock
  reason above; still good practice on Core, where the ASP.NET Core host
  has no `SynchronizationContext` to begin with, for the same reduced-overhead
  reason.
- Thread a `CancellationToken` through any async call chain that should be
  cancellable, the same way Go threads `context.Context` — see `go.md` for
  the equivalent idiom in the other direction.

## Traps
- `DateTime` has no reliable timezone identity — `DateTime.Now` vs
  `DateTime.UtcNow` plus an ambiguous `Kind` is a recurring source of
  off-by-timezone bugs. Prefer `DateTimeOffset` for anything crossing a
  process or serialization boundary — store and log timestamps as UTC,
  produced with `DateTimeOffset.UtcNow` at the point they're created, not
  a local `DateTime` converted later.
- LINQ's deferred execution: an `IEnumerable<T>` built from `.Where()`/
  `.Select()` re-runs the whole pipeline on every enumeration and on every
  side-effecting source (a DB query, a stream read) — materialize with
  `.ToList()`/`.ToArray()` once if the result is enumerated more than once
  or the source has side effects, otherwise both the query and any side
  effect happen once per enumeration.
- `.csproj` target-framework mismatches: a library built against
  `netstandard2.0` to be usable from both Framework and Core consumers
  cannot use any Core-only API without a runtime `PlatformNotSupportedException`
  from the Framework side — check `TargetFramework(s)` before assuming an
  API is available.

## Observability
- `Microsoft.Extensions.Logging` (`ILogger<T>`), or `Serilog` where the
  project already uses it, for structured logging —
  `logger.LogError("Order {OrderId} failed: {Reason}", orderId, reason)`
  message-template placeholders, not string interpolation
  (`$"Order {orderId} failed"`), so the fields stay structured in the sink
  rather than baked into a string. See `../observability.md`.

## Performance
- `BenchmarkDotNet` for benchmarking — never a hand-rolled `Stopwatch` loop,
  which misses JIT warm-up and GC effects that a real harness accounts for.
  `dotnet-trace`/PerfView for profiling. `Span<T>`/`Memory<T>` over
  allocating a new array/`string` slice for zero-copy work on contiguous
  data. See `../performance.md` before reaching for any of these.
