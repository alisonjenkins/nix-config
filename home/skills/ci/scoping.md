# Scoping: only do work the change can affect

Skipping work is safe only when a missed dependency fails toward running
more, never less. Build every scoping rule so that an unknown case runs
everything.

## Path gating

1. Diff the PR against its base: the merge commit's first parent in CI, or
   `git merge-base HEAD origin/<default>` locally. Use
   `--name-status --no-renames` so added and deleted files are visible.
2. Map each changed path to the sections it can affect, with an explicit
   allow-list of paths that affect nothing (docs, `.md` prose, specs).
3. **Run everything** when any of these holds:
   - a changed path matches no rule (unknown file types count as affecting
     everything);
   - the gate's own script, the workflow, or a shared setup action changed;
   - a lockfile, toolchain pin or top-level build file changed;
   - the base cannot be fetched or the diff is empty;
   - a manual override is set (an env var such as `CI_FULL=1`, or a label).
4. Added and deleted files are riskier than modified ones. Directory
   auto-discovery picks up a new file, and a deleted one can leave a dangling
   reference.
5. Print which sections ran and why. A skip nobody can see cannot be
   questioned.

Gate **inside** the aggregator job, not with workflow-level `paths:`
filters. A workflow that never starts never reports, and a required check
then waits forever.

The scheduled full run on the default branch is the backstop for any gap in
the rules.

## Affected tests

Prefer a tool that knows the dependency graph over hand-written path rules:

- **Build graph tools** (Bazel, Nx `affected`, Turborepo `--filter`,
  Pants) compute the affected targets from the diff.
- **Nix**: checks are derivations keyed by their inputs. An unchanged check
  is a binary-cache hit. Scope evaluation, not builds, and only when the eval
  is itself the cost.
- **Rust workspaces**: test the changed crates and their reverse
  dependencies (`cargo metadata` gives the graph), not the whole workspace.
- **Go**: `go test` caches passing packages by their inputs. Keep the cache
  (`GOCACHE`) and run `./...`; unchanged packages print `(cached)`.

Hand-written path rules are fine for a small repo. Test them, and keep the
"unknown runs everything" default.

## Incremental mutation testing

Mutation testing proves the tests can fail (see `testing`'s
`property-based.md` and the language files). A full run is too slow for
every PR, so split it:

1. **Reach a clean baseline once.** Run the full mutation suite and fix or
   justify every surviving mutant. Until the baseline is clean, a per-PR run
   reports old survivors as if the PR caused them.
2. **Per PR, mutate only what changed.** Mutate the code the diff touches,
   and also the code covered by tests the diff changes, since a weakened
   test lets old mutants through.
   - Rust: `cargo mutants --in-diff <patch>` (git diff against the base).
     `--iterate` skips mutants caught in earlier runs when the previous
     `mutants.out` is cached. `--shard k/n` splits a large run.
   - JavaScript/TypeScript: StrykerJS `--incremental` reuses
     `reports/stryker-incremental.json` from the last run; cache that file
     between runs. It does not see changes outside mutated files and tests,
     so keep the periodic full run (`--force`).
   - Go: scope `gremlins unleash` to the changed packages. Check
     `gremlins unleash --help` for a diff option in the installed version
     before relying on one.
3. **Fail the PR on any surviving mutant in changed code.** Old survivors
   are already justified in the baseline.
4. **Re-run the full suite on a schedule** (weekly is typical) and when the
   mutation tool, its config or the test runner changes. That re-establishes
   the baseline and catches what the incremental runs cannot see.
