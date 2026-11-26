# Nix inputs: flake.lock and tack

A Nix repo pins its dependencies one of two ways:

- **flake.lock**: `inputs` in `flake.nix`, locked by `nix flake lock`.
- **tack**: pins in `.tack/pins.toml`, locked into `.tack/pins.lock.json`. A
  tack flake has no `inputs` attribute and its `flake.lock` holds only the
  root node.

Some repos use both. Using the wrong tool silently does nothing or locks
the wrong file, so detect first.

## 1. Detect

Run `scripts/detect-inputs.sh [DIR]`. It prints one JSON line:

| `mode` | Meaning | Update with |
|---|---|---|
| `flake` | `flake.nix`/`flake.lock`, no `.tack/` | `nix flake update NAME` |
| `tack` | `.tack/pins.toml`, lock root-only or absent | `tack update NAME` |
| `both` | `.tack/` beside a populated `flake.lock` | each tool for its own inputs |
| `none` | neither | nothing to update |

`tack_cli` is `none`, `v1` or `v2`. nixpkgs ships the 1.x line; many
commands exist only in 2.x. Check it before you run anything from the 2.x
list in [tack.md](inputs/tack.md). Do not trust `tack --version`: nixpkgs' 1.0.0
reports `0.1.1`.

In `both` mode, find out which input lives where before touching either.
An input in `pins.toml` and in `flake.nix` `inputs` is two separate locks of
the same source. Ask whether the repo is mid-migration before "fixing" it.

## 2. Work in the repo's system

Never convert a repo as a side effect of a bump. "Update nixpkgs" in a
flake.lock repo means `nix flake update nixpkgs`, not a tack migration.

| Doing | Read |
|---|---|
| Any change in a `flake` repo, or the flake.lock half of `both` | [flake-lock.md](inputs/flake-lock.md) |
| Any change in a `tack` repo, or the tack half of `both` | [tack.md](inputs/tack.md) |
| Deciding whether to adopt tack, or migrating with `tack init --convert` | [choosing.md](inputs/choosing.md) |

## 3. When tack earns its place

Only discuss this when the user asks, or when the pain is one tack fixes.

Reach for tack when the repo needs one of these:

- **One nixpkgs for every input**: `tack dedup` and `[all_follow]` collapse
  duplicate copies. flake.lock needs a hand-written `follows` per input.
- **A patch on an input without forking it**: `tack patch add` (2.x).
- **Pins that must not move by accident**: `freeze`, or `fixed` pins that
  need `tack update --accept`.
- **Signed-commit checks on upstreams**: signers and `tack verify` (2.x).
- **Drift review before writing**: `tack look -v`.
- **Undo of a lock edit**: `tack undo` / `tack redo`.
- **Lazy fetching**: tack only fetches what an evaluation touches.

Stay on flake.lock when any of these hold:

- Other flakes consume this one and must override its inputs. A non-tack
  consumer cannot override a tack flake's inputs.
- CI or tooling reads `flake.lock`: update bots, flake-checker,
  Renovate's nix manager, scripts using `--override-input`. Converting
  breaks every one of them.
- The repo has a handful of inputs and no duplicate nixpkgs.
- Collaborators or CI images lack tack.

Costs to say out loud before recommending it:

- Undo history lives per machine in `~/.local/state/tack/`, not in git.
- Patched pins must be rebuilt on each fresh machine or CI runner.
- The nixpkgs build lags upstream by a major version.

[choosing.md](inputs/choosing.md) carries the full checklist and the migration.
