# Choosing tack, and migrating to it

## Checklist before recommending tack

Answer each from the repo, not from memory:

1. **Who consumes this flake?** Search for other repos with it as an input.
   If any exist and override its inputs, stay on flake.lock.
2. **What reads `flake.lock`?** Grep CI workflows, scripts and docs for
   `flake.lock`, `nix flake update`, `--override-input`, `flake-checker`,
   Renovate or update-bot config. Each hit is migration work, not a reason
   to skip asking.
3. **Is there a real pain tack fixes?** Duplicate nixpkgs nodes, a fork kept
   only to carry a patch, an input that keeps moving by accident, or a need
   to verify upstream signatures. No pain, no migration.
4. **Can every machine run it?** CI images, collaborators, and any host
   that evaluates the flake need `tack` for updates. Evaluation needs only
   Nix, except for patched pins.
5. **Which tack?** nixpkgs ships 1.x. Patches, freeze, signers and tag
   templates need 2.x from upstream.

Report the answers, a recommendation, and what migrating would break. The
choice is the user's.

## Migrating a flake

Do this on a branch, and expect to touch the tooling from step 2.

1. `tack init --convert`. It reads `flake.nix`'s `inputs` with `nix eval`
   and writes `pins.toml`. It copies URLs, `flake = false` (as `fetch`),
   `dir`, `submodules` and first-level `follows`. It skips names that are
   not plain identifiers.
2. Review `pins.toml` against the old `inputs`. Nested follows deeper than
   one level do not carry over.
3. Hold each pin at its old revision first. `--convert` copies URLs, not
   `flake.lock` revisions, so a bare `tack update` moves every branch that
   has moved upstream. Append `?rev=SHA` (the full `locked.rev` from
   `flake.lock`) to each git or GitHub pin, then `tack update` to write
   `pins.lock.json`. Drop the `?rev=` once step 7 passes, on the pins that
   should track a branch again.
4. Rewire `flake.nix` by hand. `--convert` never edits it. Remove `inputs`
   and import `./.tack` in `outputs` (see [tack.md](tack.md)). Or run
   `tack init --flake` in a scratch dir and copy its template.
5. `nix flake lock` leaves a root-only `flake.lock`. Keep it committed.
6. `tack dedup`, then review the `[all_follow]` lines it suggests.
7. Build every output the old lock fed. Compare store paths for a host or
   two to confirm nothing moved that you did not bump.
8. Update the tooling from checklist step 2, in the same branch or first.

## Running both

`both` is fine as a deliberate split, such as tack for a subproject's
`.tack/` and flake.lock for the top-level flake. It is a trap when the same
source is pinned in both: the two locks drift. Name the owner of each input
and remove the duplicate.
