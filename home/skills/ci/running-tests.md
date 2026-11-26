# Running tests in CI

## What the PR check runs

The PR check runs everything a reviewer would otherwise have to trust:

1. Format and lint (seconds; run first so a typo fails in under a minute).
2. Build or evaluate everything the change can affect.
3. Unit and integration tests.
4. Mutation tests on the changed code, once the repo has a clean baseline
   (see [scoping.md](scoping.md)).

Slow suites that cannot be scoped (full end-to-end, full mutation, every
platform) run on a schedule against the default branch and open an issue
when they fail. They never become an unwatched nightly that is always red.

## Commands

- Use the runner the `testing` language file names, in its CI form:
  `cargo nextest run` (with `--profile ci` if the repo defines one),
  `pytest -p no:cacheprovider`, `vitest run` (not watch mode),
  `go test -race ./...`, `nix build .#checks.<system>.<name>`.
- Pin the toolchain the same way locally and in CI: a lockfile, a
  `rust-toolchain.toml`, a Nix dev shell. A version that floats in CI
  turns an upstream release into a red build on an unrelated PR.
- Make the run hermetic: no network in tests, a fixed timezone and locale
  (`TZ=UTC`, `LC_ALL=C.UTF-8`), no dependence on the runner's home
  directory.
- Emit machine-readable results (JUnit XML or the runner's JSON) so the CI
  UI shows which test failed without reading the log.

## Ordering and parallelism

- Cheap checks first, and `fail-fast` off for a matrix: one red platform
  should not hide whether the others pass.
- Run independent sections concurrently inside one job when setup (checkout,
  toolchain, cache restore) dominates. Split into separate jobs when sections
  need different machines or the job would outgrow its memory limit.
- Concurrent sections share the runner's memory. Sum their peaks before
  adding another.
- Cancelling must reach every child. A trap that kills only the direct
  children leaves grandchildren (compilers, `nix` clients) running into the
  next run. Start each section in its own process group (`set -m` in bash)
  and signal the group (`kill -- -<pid>`).
- A section that dies without writing its result marker (disk full, OOM
  kill) counts as failed immediately. Waiting for the marker burns the whole
  job timeout.

## Sharding

Shard only after scoping and caching, since sharding multiplies setup cost.
Use the runner's own split (`cargo nextest --partition`,
`cargo mutants --shard k/n`, `vitest --shard`, `pytest-split` by recorded
durations) so every test lands in exactly one shard.

## Local runs of the same script

The script that CI runs must be safe to run in a developer's clone. For
example, `git fetch --depth=1` is harmless on a CI checkout but makes a full
local clone shallow, which breaks `merge-base`. Pass `--depth` only when
`git rev-parse --is-shallow-repository` is already true.
