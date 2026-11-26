# Working in a tack repo

tack keeps pins in `.tack/`:

- `pins.toml`: what you edit, or let `tack add`/`rm` edit.
- `pins.lock.json`: what Nix reads. Commit it with `pins.toml`.
- `default.nix`: the resolver. Leave it to `tack init --resolver`. Deleting
  its "tack-managed" marker line takes ownership of the file from tack.
- `patches/`: vendored patches (2.x). Commit them.

A tack flake imports the resolver instead of declaring `inputs`:

```nix
outputs = args: let
  inputs = (import ./.tack) { overrides = args.tackOverrides or { }; };
in { ... };
```

Downstream tack projects reach these pins through `tackOverrides` only
when `pins.toml` sets `[tack] recomposable = true`. `tack init` sets it when
`flake.nix` already threads `tackOverrides`; after rewiring by hand, set it
yourself. A flake nobody overrides can leave it off.

Its `flake.lock` stays at the root node only. Do not run
`nix flake update` to bump a tack pin. It rewrites nothing useful.

## Commands

Check `tack --help` first, or `detect-inputs.sh`'s `tack_cli`.

Present since 1.x:

| Goal | Command |
|---|---|
| Bump one pin, or all | `tack update NAME`, `tack update` |
| Relock a drifted `fixed` pin | `tack update --accept NAME` |
| See drift without writing | `tack look [-v] [NAME]` |
| Add a pin | `tack add NAME URL` (`--fetch` for a source tree, `--fixed` for a fixed-output download, `--follows child=parent`) |
| Pin one commit | `tack add NAME 'github:o/r?rev=SHA'` |
| Remove a pin | `tack rm NAME` |
| Collapse duplicate sources | `tack dedup` |
| Undo or redo the last edit | `tack undo [--list]`, `tack redo` |
| Shorturl alias | `tack alias NAME 'template/{path}'` |
| Scaffold or refresh | `tack init`, `tack init --resolver` |

Added in 2.x:

| Goal | Command |
|---|---|
| Skip pins or groups | `tack update --exclude NAME` (also on `look`, `tree`) |
| Show the follows graph | `tack tree [NAME]` |
| Hold a pin still | `tack freeze NAME`, `tack unfreeze NAME` |
| Follow newest matching tag | `tack add NAME URL --tag 'v{version}'` |
| Patch an input | `tack patch add NAME URL-or-FILE`, `patch update`, `patch rm` |
| Rebuild patched trees on this machine | `tack materialize [NAME]` |
| Require signed upstream commits | `tack signer add NAME KEY`, set `signers = ["NAME"]` on each pin to protect, then `tack verify [--base REF]` |

On 1.x, say the command needs 2.x. Do not hand-edit `pins.lock.json` to
fake it.

## Pin kinds and follows

- **flake** (default): evaluated as a flake.
- **fetch**: a source tree only, like `flake = false`.
- **fixed**: a fixed-output download. Changing it needs `--accept`.

Follows work at three levels:

- Per pin: `follows = { nixpkgs = "nixpkgs" }`.
- Top level: `child = { follows = "pin/input" }`.
- Repo wide: `[all_follow]`, which `tack dedup` suggests. The CLI cannot set
  it; edit `pins.toml`.

`exclude_follow`, `omit_inputs` and `keep_inputs` trim what follows applies to.

## Gotchas

- **Frozen pins**: `tack update NAME` on a frozen pin moves it and
  re-freezes it. A bare `tack update` leaves it alone.
- **Patched pins on a fresh machine or CI**: eval fails with "the patched
  tree of X is not in the store". Run `tack materialize`. Without the CLI,
  `nix-build .tack -A _patched -o .tack/patched` does the same.
- **Group-level patches** stay after the fix lands upstream. `tack patch rm`
  refuses a patch inherited from a group: delete it from the group's
  `patches` list in `pins.toml`, then `tack patch update NAME...` for the
  group's pins and rebuild.
  `tack patch rm NAME SOURCE` is for a patch set on the pin itself.
- **`tack verify` passes when nothing is protected**: it skips pins with no
  `signers` list and prints `no pins have signers`. `tack signer add` only
  registers a key; the CLI cannot assign it, so edit `pins.toml`. Check the
  output names every pin you meant to protect.
- **Undo is local**: history is per machine and per checkout path. A fresh
  clone cannot undo a colleague's update. Use git for that.
- **Local paths**: upstream recommends `git+file://` over `path:`.
- **Deep shorturls**: `github:o/r/sub/dir` reads `sub/dir` as a branch. Use
  `--dir` for a subdirectory.
- **Consumers**: a flake without tack cannot override this flake's inputs,
  even with `[tack] recomposable = true`.

## Verify

After any change:

1. `git diff .tack/` shows only the pins you meant to move.
2. Build or eval the thing the pin feeds (`nix flake check`, a host build).
3. Commit `pins.toml`, `pins.lock.json`, `patches/` and any `keys/` files
   `tack signer add` wrote together. An SSH key stays inline in `pins.toml`;
   a GPG key or key file is copied to `.tack/keys/`.
