# Performance

Performance work follows measurement, not intuition. The order is always:
profile to find where time actually goes, benchmark the specific change to
prove it moved the number, and only then reach for something like SIMD if the
profile says the bottleneck is data-parallel scalar work. Skipping straight to
"this should be faster" produces code that is harder to read and not
measurably faster — the worst of both.

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

The cheapest speedup available is the copy you never make. Before reaching
for a faster algorithm or SIMD, check whether the hot path is dominated by
allocation and memcpy rather than actual computation — a profile with wide
bars in `memcpy`/`alloc`/a constructor is the signal, not a guess.

- **Borrow across a boundary instead of cloning to satisfy the type system.**
  A function that takes owned data (`String`, `Vec<T>`, a fully materialized
  object) when it only reads the data forces every caller to copy, whether or
  not that caller already owns something borrowable. Take `&str`/`&[T]` (or
  the language's equivalent read-only view) and let the few callers that
  truly need ownership clone at their own call site — see
  `languages/rust.md`'s
  "prefer borrowed parameters" idiom, which is this rule's Rust-specific
  form.
- **Parse or deserialize into views over the original buffer, not fresh
  allocations per field**, when the source buffer already outlives the
  parsed result: a `&str` slice into the original JSON/log buffer instead of
  a `String` copy per field, a struct of offsets into a `mmap`'d file instead
  of reading it into owned buffers first. This is the difference between an
  O(1) parse and an O(n) one for anything dominated by string/byte
  extraction. It has a real cost: the view now carries the source buffer's
  lifetime, and the source cannot be freed, mutated, or reused for another
  read while a view into it is still alive — worth it exactly when the
  buffer's lifetime already covers the view's use, not when it forces the
  buffer to be kept alive artificially.
- **Reuse a buffer across iterations instead of allocating one per call**,
  in any hot loop that produces output of a bounded or predictable size:
  clear and refill a `Vec`/`bytearray`/`ArrayBuffer` rather than constructing
  a new one each pass. This is what a "no allocation in the steady state"
  design looks like in practice, and it is a much larger win than it looks —
  allocator and GC pressure often dominate a hot loop more than the
  work happening inside it.
- **Memory-map large files read sequentially or randomly-accessed by
  section**, instead of reading the whole file into a heap buffer first,
  when the access pattern does not need the entire file resident at once.
  The OS page cache then does the buffering, and repeated reads of the same
  region cost nothing after the first fault.
- **Zero-copy is a lifetime/ownership tradeoff, not a free win — benchmark
  it.** A borrowed/mapped/reused-buffer version can lose to a straightforward
  copy when the "zero-copy" path adds indirection, defeats the compiler's
  ability to keep the data in registers, or forces awkward lifetime
  threading that pushes complexity onto every caller. Apply this after
  profiling shows copying is the actual cost, and confirm the win with a
  benchmark (see Benchmarking above) rather than assuming "avoids a copy"
  always means "faster."

## SIMD

Reach for SIMD only once profiling has identified a hot, data-parallel,
branch-light scalar loop — summing, comparing, transforming a large
contiguous buffer of primitives — and a benchmark confirms the scalar version
is actually the bottleneck at the relevant input size. It is the highest-cost,
least-portable tool here; use it last, not first.

- **Prefer the compiler's auto-vectorizer before hand-writing intrinsics.**
  A tight scalar loop over a `&[f32]`/contiguous array with no data-dependent
  branching and no aliasing between input and output slices auto-vectorizes
  under `-O3`/`--release` in most compilers without any code change. Check
  the generated assembly or the compiler's vectorization report
  (`-Rpass=loop-vectorize` for LLVM-based compilers) before assuming
  intrinsics are needed at all.
- **Prefer a portable abstraction over target-specific intrinsics** when the
  language has one: Rust's portable SIMD (`std::simd`, where the toolchain
  supports it) or a crate like `wide`
  before hand-written `_mm256_*` AVX2 intrinsics; a runtime-dispatched crate
  (`multiversion`, `simdeez`-style) when the binary must run on machines with
  different instruction set extensions. Hand-written per-ISA intrinsics are a
  last resort for the specific hot loop that measurably needs them, gated
  behind a runtime CPU-feature check (`is_x86_feature_detected!` or
  equivalent) with a scalar fallback — never assume the deploy target has
  AVX2/NEON/etc.
- **Aliasing and alignment are the correctness traps, not the speed traps.**
  SIMD loads/stores over unaligned or overlapping memory are undefined
  behaviour or silently wrong in exactly the way that passes a quick manual
  test and fails on a different input size or a different CPU. Use the
  language's checked/aligned load functions, not a raw pointer cast, unless
  you have specifically verified alignment.
- **Benchmark the vectorized version against the scalar one on the actual
  target CPU**, not a different machine's ISA — a SIMD width or instruction
  latency difference between, say, an AVX2 dev laptop and an AVX-512 or ARM
  NEON deploy target can flip which version is actually faster.
- Document the assumption that made vectorization valid (no aliasing, no
  cross-lane data dependency, the specific ISA feature required) as a comment
  at the site — this is exactly the kind of non-obvious constraint that
  `programming`'s "comment why, not what" rule exists for, because the next
  editor who changes the loop's data dependency will silently reintroduce a
  correctness bug the original benchmark never tested for.
