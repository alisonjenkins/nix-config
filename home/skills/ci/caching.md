# Caching

A cache is correct only if a hit gives the same result as a clean build.
Everything below follows from that.

## Keys

- Key on the inputs that decide the content: the lockfile hash
  (`hashFiles('**/Cargo.lock')`, `package-lock.json`, `go.sum`,
  `flake.lock`), the toolchain version, and the OS and architecture.
- Use `restore-keys` for a prefix fallback (an older cache still saves most
  downloads), but save under the exact key only.
- Never key on the commit SHA alone. Every run misses, and the cache store
  fills with entries nobody reads.

## What to cache

| Cache | Worth it | Notes |
|---|---|---|
| Downloaded dependencies (registry, `node_modules` from a lockfile, Go module cache) | Yes | Cheapest win. Prefer the language's setup action's built-in cache. |
| Compiler output via a content-addressed wrapper (`sccache`, `ccache`) | Yes | Keyed per compilation unit, so a stale entry cannot be wrong. Turn off incremental compilation (`CARGO_INCREMENTAL=0`); it does not mix with sccache. |
| Whole `target/` or build directories | Rarely | Large, slow to restore, grows without bound. Only with a size cap and a sweep. |
| Nix store paths | Yes, via a binary cache | Push build results to a binary cache (Cachix, attic, a self-hosted store), not `actions/cache` of `/nix/store`. Nix already keys by input hash. |
| Test results | Only in a tool built for it | Bazel, Nx, Turborepo and Nix checks key results by inputs. A hand-rolled "skip if passed before" cache is a scoping rule, see [scoping.md](scoping.md). |

Measure the restore time against the work it saves. A 2 GB cache that takes
90 s to restore and saves 60 s of compiling is a loss.

## Safety

- **Fork PRs must not write the cache.** A malicious PR can poison an entry
  that the default branch then restores. GitHub scopes cache writes per
  branch; keep it that way, and never use `pull_request_target` to run
  untrusted code with cache or secret access.
- The default branch's caches are the shared base. PR branches read them and
  write their own.
- Caches are evicted (GitHub: 10 GB per repo, least recently used first).
  Design for a cold miss: the job must still pass, only slower.

## Self-hosted runners

- A persistent runner keeps its Nix store, sccache directory or Docker layer
  cache between jobs. That is faster than any upload. It needs a size cap,
  and garbage collection that runs **between** jobs, not when the disk is
  already full mid-build.
- Leave free-space headroom for the largest build. A daemon that starts its
  own garbage collection under disk pressure can crash the build it was
  meant to save.
