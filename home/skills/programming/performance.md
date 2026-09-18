# Performance

Performance work follows measurement, not intuition. The order is always:
profile to find where time actually goes, benchmark the specific change to
prove it moved the number, and only then reach for something like SIMD if the
profile says the bottleneck is data-parallel scalar work. Skipping straight to
"this should be faster" produces code that is harder to read and not
measurably faster — the worst of both.

## Tools per language

| Language | Profiling | Benchmarking | SIMD/vectorization | Zero-copy |
|---|---|---|---|---|
| Rust | `cargo flamegraph` | `criterion` | `std::simd`, `is_x86_feature_detected!` | `Cow<'a, T>`, borrowed `&str`/`&[T]`, `bytes`/`zerocopy` crates |
| Python | `py-spy`, `scalene` | `pyperf`, `pytest-benchmark` | `numpy` vectorized ops | `memoryview`, `mmap` |
| TypeScript/Node | `clinic.js`, `0x` | `tinybench`, `mitata` | — | `ArrayBuffer`/`TypedArray` views (`subarray`, not `slice`) |
| Shell | `perf` | `hyperfine` | — | — |
| Go | `pprof` (`go tool pprof`, `net/http/pprof`) | `go test -bench=.` (`testing.B`) | — | — |
| C# | `dotnet-trace`, PerfView | `BenchmarkDotNet` | — | `Span<T>`/`Memory<T>` |

## Profiling first

Never optimise from a guess about which function is slow. Guesses are wrong
often enough that "optimising" the wrong function is the default outcome, not
an edge case.

- **Sampling profiler over manual timing** for finding the hot path:
  `perf record`/`perf report` (Linux, any compiled language), `py-spy` or
  `scalene` (Python, no code changes needed), `0x` or `clinic.js` flamegraphs
  (Node/TypeScript), `cargo flamegraph` (Rust, wraps `perf`). A flamegraph
  answers "where does time go" in one pass; scattered `time.time()` calls
  answer it one guess at a time.
- **Profile a realistic workload**, not a microbenchmark's input. A profile
  built on a 10-item test fixture will point at setup and warm-up costs, not
  the algorithmic hot path that shows up at real scale.
- **Re-profile after the fix.** The bottleneck you fixed is rarely the only
  one; the next-hottest function is now the new bottleneck, and it may not be
  the one you expected.
- Distinguish CPU-bound from I/O- or lock-bound before reaching for SIMD or
  algorithmic rewrites: a flamegraph showing wide bars in `read`/`recv`/futex
  wait means the fix is concurrency or I/O batching (see `concurrency.md`),
  not vectorization.

## Benchmarking

A benchmark exists to answer one question: did this specific change make
this specific code measurably faster, on this machine, for this input shape.
Anything a benchmark harness does not control for turns that question into a
guess again.

- **Use a real benchmarking harness**, not a hand-rolled loop with
  `time.time()`/`Instant::now()` around it: `criterion` (Rust), `pyperf` or
  `pytest-benchmark` (Python), `tinybench` or `mitata` (TypeScript/Node),
  `hyperfine` (any CLI/process-level benchmark). A hand-rolled timer misses
  warm-up, JIT/cache effects, and statistical noise that a real harness
  accounts for — the number it prints looks precise and is not.
- **Report a distribution, not a single number.** Wall-clock time on a shared
  machine varies run to run; a harness that reports mean + variance (or
  median + percentiles) tells you whether a 3% difference is a real effect or
  noise. A single before/after number cannot.
- **Pin down what varies.** Same machine, same input size and shape, same
  build flags (`--release` for Rust, not a debug build), background load
  quiesced. A benchmark run on a laptop under thermal throttling, or against
  a debug build, measures the throttling or the missing optimizations, not
  the change.
- **Benchmark the boundary a caller actually crosses**, not an internal
  helper in isolation, unless that helper is the proven bottleneck from
  profiling. A micro-benchmark of a function that is 2% of total runtime
  proves nothing about the program's actual speed.
- Commit the benchmark alongside the change it justifies, the same way a bug
  fix ships with a regression test (see `testing` skill) — a performance
  claim with no reproducible benchmark cannot be checked by the next person,
  including future-you.

## Zero-copy

Apply only once a profile shows wide bars in `memcpy`/`alloc`/a constructor —
not as a default style.

- Borrow across a boundary (`&str`/`&[T]`) instead of cloning to satisfy the
  type system; let only the callers that truly need ownership clone at their
  own call site — see `languages/rust.md`'s "prefer borrowed parameters".
- Parse or deserialize into views over the original buffer (a `&str` slice
  into the source, a struct of offsets into a `mmap`'d file), not fresh
  allocations per field, when the source buffer already outlives the parsed
  result. The view then carries the source's lifetime — the source cannot be
  freed, mutated, or reused while the view is alive.
- Reuse a buffer across iterations instead of allocating one per call, in any
  hot loop with bounded/predictable output size.
- Memory-map large files instead of reading them fully into a heap buffer
  first, when the access pattern doesn't need the whole file resident.
- Benchmark it. A borrowed/mapped/reused-buffer version can lose to a plain
  copy when it adds indirection or forces awkward lifetime threading —
  confirm the win (see Benchmarking above) rather than assuming it.

## SIMD

Reach for it only once profiling has identified a hot, data-parallel,
branch-light scalar loop and a benchmark confirms the scalar version is the
bottleneck at the relevant input size. Highest-cost, least-portable tool
here; use it last.

- Prefer the compiler's auto-vectorizer before hand-writing intrinsics — check
  the generated assembly or vectorization report (`-Rpass=loop-vectorize` for
  LLVM) before assuming intrinsics are needed at all.
- Prefer a portable abstraction (Rust's `std::simd`, a `wide`/runtime-dispatch
  crate) over target-specific intrinsics. Hand-written per-ISA intrinsics are
  a last resort, gated behind a runtime CPU-feature check
  (`is_x86_feature_detected!` or equivalent) with a scalar fallback — never
  assume the deploy target has AVX2/NEON/etc.
- Use the language's checked/aligned load functions, not a raw pointer cast,
  unless alignment is specifically verified — unaligned/overlapping SIMD
  access is UB or silently wrong, and the failure mode is passing on one
  input size/CPU and breaking on another.
- Benchmark the vectorized version against the scalar one on the actual
  target CPU, not a different machine's ISA.
- Document the assumption that made vectorization valid (no aliasing, no
  cross-lane data dependency, the specific ISA feature required) as a comment
  at the site, per `programming`'s "comment why, not what" rule.
