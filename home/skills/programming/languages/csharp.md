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
  build tools). Package references are usually still `PackageReference`-style
  in a modern `.csproj`, but an older codebase may use `packages.config`;
  check before assuming `dotnet restore` alone covers it.
- Check the project's `<TargetFramework>` and `<LangVersion>` in its
  `.csproj` before assuming a newer language feature (nullable reference
  types, records, `required` members, top-level statements) is available.
  These are compiler/LangVersion features, not Core-only: they work on
  Framework with a modern SDK and an explicit `<LangVersion>` override, but a
  Framework project is commonly pinned to an older language version even when
  the installed SDK supports newer syntax. `dotnet --version`/
  `msbuild -version` reports only the installed SDK/MSBuild version, not what
  the project targets, so it says nothing about which features this project
  can use.

## Guard rails (mandatory)
- **`<Nullable>enable</Nullable>`** in every `.csproj` that can have it
  (Core, and Framework projects on a modern-enough SDK/LangVersion). The C#
  equivalent of `rust.md`'s clippy deny list and `typescript.md`'s
  `noUncheckedIndexedAccess`: without it, `string` and `string?` are the same
  type to the compiler, so a null becomes a `NullReferenceException` at the
  access site instead of a compile error where it was introduced. A project
  that can't yet go fully nullable-enabled should enable it and use
  `#nullable disable` only on files still needing triage, not skip it
  project-wide.
- **`<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`** (or the specific
  analyzer rule IDs that matter). An enabled-but-not-enforced analyzer is
  advisory and gets ignored under deadline pressure; see `defensive.md`'s
  "Guard rails".
- `dotnet test` (or the project's test runner) with code coverage wired into
  CI where the project already tracks it; do not introduce a new coverage
  gate as a drive-by in an unrelated change.

## Idioms
- **Exceptions are for the exceptional**, not expected control flow. A lookup
  that can reasonably fail (parse a value, find an entry) uses
  `TryParse`/`TryGetValue`-style methods or returns a nullable/`Result`-style
  type; reserve `throw` for a genuine contract violation or unrecoverable
  state. `defensive.md`'s assertions-vs-error-handling table maps directly
  onto "exception for a bug" vs "`Try*`/nullable for something that can
  happen."
- **`throw;` to rethrow, never `throw ex;`.** `throw ex;` resets the stack
  trace to the rethrow site, destroying the information that identified where
  the exception originated. The most common C# defect in a `catch` block, and
  silent until you need the trace and it is gone.
- **Catch the specific exception type.** A bare `catch (Exception)` needs a
  comment saying why the broad catch is correct, and must either rethrow
  (`throw;`) or log with the full exception, not swallow it. An empty
  `catch { }` is never acceptable outside a documented, deliberate
  best-effort cleanup path.
- `using`/`await using` for anything `IDisposable`/`IAsyncDisposable`: C#'s
  form of `defensive.md`'s "finish what you start." A manual `Dispose` at the
  end of a long method is skipped by the first early return or exception;
  `using` is not.
- Records (`record`/`record struct`) for immutable domain data; `init`-only
  properties over public mutable setters when the type is a value rather than
  an entity with a lifecycle. C# 9+/10+ features, so usable on Framework too
  with a modern SDK and `<LangVersion>` set high enough (see Toolchain).
- `readonly record struct CustomerId(Guid Value)`, not a bare `Guid`;
  mandatory per `defensive.md`'s "distinct domain concepts" rule (see the
  Toolchain note on LangVersion for Framework).
- `CultureInfo.InvariantCulture` for any string comparison, parse, or
  formatting that is not user-facing display text. `ToUpper()`/`ToLower()`/
  `string.Compare` under the current culture silently differ on a machine
  with another locale (the classic "Turkish I" bug: `"i".ToUpper()` is not
  always `"I"`).

## Async
- **Never `async void`** except an event handler, where the framework
  requires it. An `async void` method's exceptions cannot be `await`ed or
  caught by the caller; they crash the process (or are silently lost,
  depending on the host) instead of propagating.
- **Never `.Result` or `.Wait()` on a Task from synchronous code.** On .NET
  Framework (and any code still capturing a `SynchronizationContext`, e.g.
  classic ASP.NET or WinForms/WPF UI threads) this is the canonical async
  deadlock: the continuation cannot resume on the captured context because
  that thread is blocked waiting for it. `async` all the way up instead.
- `ConfigureAwait(false)` on every `await` inside library code (not
  application/UI entry points) that need not resume on the original context.
  Mandatory on .NET Framework libraries for the deadlock reason above; still
  good practice on Core, where the ASP.NET Core host has no
  `SynchronizationContext`, for the reduced overhead.
- Thread a `CancellationToken` through any async call chain that should be
  cancellable, as Go threads `context.Context` (see `go.md`).

## Traps
- `DateTime` has no reliable timezone identity: `DateTime.Now` vs
  `DateTime.UtcNow` plus an ambiguous `Kind` is a recurring source of
  off-by-timezone bugs. Prefer `DateTimeOffset` for anything crossing a
  process or serialization boundary. Store and log timestamps as UTC,
  produced with `DateTimeOffset.UtcNow` when created, not a local `DateTime`
  converted later.
- LINQ's deferred execution: an `IEnumerable<T>` built from `.Where()`/
  `.Select()` re-runs the whole pipeline, and any side-effecting source (a DB
  query, a stream read), on every enumeration. Materialize once with
  `.ToList()`/`.ToArray()` if the result is enumerated more than once or the
  source has side effects.
- `.csproj` target-framework mismatches: a library built against
  `netstandard2.0` for both Framework and Core consumers cannot use any
  Core-only API without a runtime `PlatformNotSupportedException` on the
  Framework side. Check `TargetFramework(s)` before assuming an API is
  available.

## Observability
- `Microsoft.Extensions.Logging` (`ILogger<T>`), or `Serilog` where the
  project already uses it, for structured logging:
  `logger.LogError("Order {OrderId} failed: {Reason}", orderId, reason)`
  message-template placeholders, not string interpolation
  (`$"Order {orderId} failed"`), so fields stay structured in the sink. See
  `../observability.md`.

## Performance
- Profiling/benchmarking/zero-copy tools: see `../performance.md`'s tool
  table first. Never a hand-rolled `Stopwatch` loop for benchmarking; it
  misses the JIT warm-up and GC effects a real harness accounts for.
