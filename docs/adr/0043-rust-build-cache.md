# 0043. Share Rust compilation through sccache and sweep stale target directories

- Status: Accepted
- Date: 2026-10-16

## Context

Many git worktrees and Claude Code agents each build Rust into their own
`target` directory. On ali-desktop, 14 target directories held about 88 GiB
and `/home` (ext4, 938G) reached 100%. Four of them held 72 GiB. One of those
(29 GiB) sat inside an abandoned `.claude/worktrees/*` agent worktree.

## Decision

A home-manager module, `home/modules/rust-build-cache`
(`modules.rustBuildCache`), is on by default for every host that uses
`modules.desktop`. The switch is `modules.desktop.rustBuildCache.enable`
(default true), applied through `home-manager.sharedModules`. The module:

- Writes `~/.cargo/config.toml` with sccache as `build.rustc-wrapper`,
  `build.incremental = false`, `[profile.dev] debug = "line-tables-only"` and
  `split-debuginfo = "unpacked"`, and `[env] SCCACHE_CACHE_SIZE` (default 20G).
- Installs sccache and cargo-sweep.
- Runs a systemd user timer daily: `cargo-sweep sweep --recursive --hidden
  --time 1 ~/git`, at nice 19 with idle IO class.

Why these settings:

- `--hidden` is required. `--recursive` skips dot-directories by default (the
  log says `skip hidden folder`), so without it every
  `.claude/worktrees/*/target` is missed.
- `--time` takes whole days only. `0.5` fails with `invalid digit found in
  string`, and `--time 0` would delete everything. One day is the floor.
- The first default was 14 days. A dry run over `~/git` freed 0.9 GiB at 14
  days, 13.61 GiB at 3 days and 14.78 GiB at 1 day, so the default is 1 day.
  The first real sweep freed 14.78 GiB (`/home` went from 71G to 84G free).
- sccache cuts the cost of the rebuilds that the sweep causes (10.5s to 4.2s
  on the measured project, see Evidence) and shares compiled crates between
  worktrees. Linking and other uncacheable steps still run every time.

Related PRs: #643 (module and desktop wiring), #644 (default age 14 to 1 day).

## Alternatives rejected

- **One shared `CARGO_TARGET_DIR` per repo.** Parallel agents block on cargo's
  build lock, and one `cargo clean` wipes everyone's build. Cargo's own
  cross-workspace cache is only a 2026 goal (rust-lang/cargo#5931, see the
  [project goal](https://rust-lang.github.io/goals/2026/cargo-cross-workspace-cache.html)).
- **`cargo-sweep --maxsize`.** Adaptive per target directory. Not tried.
- **A custom `find` script for ages under one day.** More code to maintain
  for a small gain.
- **A reflink filesystem.** `/home` is ext4, so this is a migration.

## Consequences

- Every project rebuilds once after the switch.
- `line-tables-only` reduces the variable information a debugger can show.
- The sweep trims inside `target` only. It does not remove abandoned
  worktrees, so those still need deleting by hand.
- The module also applies to the other desktop hosts (framework, work laptop,
  mba-linux, Steam Deck). `~/git` may not exist there, but cargo-sweep exits 0
  for a missing root and for one with no Rust projects (both run on
  2026-10-16), so the unit does not fail. Whether it sweeps anything useful
  there depends on where each host keeps its checkouts.
- Whether the sweep age counts from atime or mtime is unverified.

## Evidence

Measured 2026-10-16 on one project, claude-monitor (about 140 crates):

| Run | Time | sccache hits / misses |
|---|---|---|
| No wrapper | 10.5s | n/a |
| sccache, empty cache | 10.6s | 0 / 140 |
| sccache, warm cache, `target` wiped | 4.2s | 138 / 0 |
| Same sources copied to a different path, warm cache | 4.7s | 138 / 0 |

- Filling the cache costs nothing measurable.
- Hits are shared across worktrees at different paths when the sources are
  identical.
- 43 "non-cacheable calls" remained. They are probably linking, build scripts
  and final binaries, but that was not broken down.

Not measured: a worktree on a different commit, larger projects (pharos,
niri), and the disk saved by the profile change alone.

Commands: `sccache --zero-stats` then `sccache --show-stats` around each build,
and `cargo-sweep sweep -d -r --hidden --time N ~/git` for the dry-run sizes.
The first real sweep ran with `systemctl --user start cargo-sweep.service`.

## Revisit when

- Cargo ships its cross-workspace build cache (rust-lang/cargo#5931). It would
  replace sccache for dependency sharing and may make the sweep unnecessary.
- `sccache --show-stats` shows a low hit rate on real work, for example because
  worktrees on different commits miss far more than the identical-source test
  did.
- `/home` is still short of space with the sweep running. Then try
  `cargo-sweep --maxsize`, or delete abandoned worktrees.
- The sweep's age turns out to count from mtime and removes files a build still
  needs, or from atime and removes almost nothing on a `relatime` mount.
