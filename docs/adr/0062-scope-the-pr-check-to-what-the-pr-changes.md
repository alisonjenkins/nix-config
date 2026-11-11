# 0062. Scope the PR check to what the PR changes

- Status: Accepted
- Date: 2026-11-11

## Context

After ADR 0044 the `flake-check` job still ran every section on every PR:
2–6 min each, mostly the seven aarch64 host evals and the `rea-ghidra`
check, which fetches 1.5 GiB of Ghidra and JDK. Most PRs touch only skills,
docs or scripts. Run 43020135653 changed one prose file and still spent
5.5 min evaluating hosts, building REA and triggering a 54 GB auto-GC.

## Decision

`.github/scripts/pr-check-x86_64-linux.sh` diffs the working tree against
the fetched base branch (`git diff --name-status --no-renames FETCH_HEAD`)
before starting any section, and starts only the sections the diff can
affect:

| Section | Runs when |
|---|---|
| modules, overlays, devShells | any change that can alter an eval |
| packages | such a change outside `flake-modules/hosts/`, or a package's own source changed (that one is built, as before) |
| aarch64 host evals | any change that can alter an eval; if all of them sit in `flake-modules/hosts/<dir>/`, only hosts named `<dir>` or `<dir>-*` |
| each bats check, `rea-ghidra` | a path its derivation copies in changes |
| CurseForge paths, skill frontmatter | always (seconds) |

A change "can alter an eval" unless one of these holds:

- No nix expression reads the path (`docs/` except `docs/token-efficiency/`,
  `specs/`, `.claude/`, `.github/`, the root markdown, `justfile`,
  `renovate.json`).
- The file was modified, not added or deleted, and has a plain-content
  extension (`.md`, `.sh`, `.py`, `.rs`, `.lua`, ...). Such a file reaches
  a build, never the evaluation.

Unknown extensions count as evaluated. So do `.json`, `.toml`, `.yaml` and
`.lock` files, since nix parses some of them (`importJSON`,
`importCargoLock`). Added and deleted files count too, since `readDir`
auto-discovers `home/skills/` and other directories, and a deleted file can
leave a dangling path.

Every section runs when any of these changes: `flake.nix`, `flake.lock`,
`overlays/`, `lib/`, `flake-modules/` outside `hosts/`, the gate's own
script, workflow or setup action. Every section also runs when the base
cannot be fetched or the diff is empty. `PR_CHECK_FULL=1` forces it. The
nightly lock PR always changes `flake.lock`, so it always gets the full
run.

## Things that are not obvious

- **The diff is against the working tree, not `HEAD`.** In CI they are the
  same (the PR's merge commit). Locally, `just check` then scopes to
  uncommitted edits too. Those are what `nix eval` sees in a dirty tree.
- **The host filter is applied before the platform test** in the
  `builtins.filter` expression. `&&` short-circuits, so hosts that are not
  candidates are never evaluated.
- **The `-suffix` match is deliberate.** `home-vpn-gateway-1-vm` imports
  `home-vpn-gateway-1`'s modules. Over-matching (`ali-mba` also selects
  `ali-mba-linux`) only costs one extra eval.

## Alternatives rejected

- **Compare drvPaths between base and head.** This is exact, but the eval it
  needs is the cost being cut.
- **Trace which files the evaluation reads.** Nix copies the whole flake
  source to the store, so nothing records per-file reads.
- **Skip only docs-only PRs.** Most PRs touch skill files or scripts under
  `home/`, so this would rarely skip anything.
