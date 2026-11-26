# 0001. One nix-inputs skill that detects flake.lock or tack before acting

- Status: Accepted
- Date: 2026-11-26

## Context

Skills only knew flake.lock. `security` and `programming` told agents to run
`nix flake update NAME`. tack (manic-systems/tack) replaces flake `inputs`
with `.tack/pins.toml` and `.tack/pins.lock.json`. In a tack flake,
`nix flake update` changes nothing, because `flake.lock` holds only the root
node. Repos can also use both at once, deliberately or mid-migration.

The user asked for skills that use tack, keep full flake.lock awareness,
handle repos with either or both, and know when and why to choose tack.

Two facts shaped the design:

- nixpkgs ships tack 1.0.0. Upstream is at 2.0.0. Patches, freeze, signers,
  `tree`, `verify`, `materialize`, `--exclude` and tag templates are 2.x only.
- nixpkgs' 1.0.0 binary reports `tack --version` as `0.1.1`. The version
  string cannot gate commands.

## Decision

1. Add a leaf skill `nix-inputs`. `SKILL.md` holds detection, a routing
   table, and the when/why decision rule. `tack.md`, `flake-lock.md` and
   `choosing.md` hold the detail.
2. Add `scripts/detect-inputs.sh`, which reports `mode` (`flake`, `tack`,
   `both`, `none`) as JSON. A root-only `flake.lock` beside `.tack/pins.toml`
   counts as `tack`, not `both`.
3. Gate 2.x commands on `tack --help` listing `verify`, `freeze` or `tree`,
   not on the version string.
4. The skill never converts a repo as a side effect of a bump. Adopting
   tack is a recommendation with a checklist, and the choice is the user's.
5. Keep repo-specific tooling out of the shared skill. It says generically
   to look for CI and scripts that read `flake.lock`. This repo's own list
   lives in its `AGENTS.md`.

## Alternatives rejected

- **Add tack to `programming/languages/nix.md`.** That file is about writing
  Nix. Input management is a workflow, read when bumping, not when writing.
- **Add tack to `infra`.** `infra` is deploy. Bumping an input is not.
- **A tack-only skill.** Every bump would need a second skill to know when
  not to use it. One skill that detects first keeps the "which system" check
  in one place.
- **Gate on `tack --version`.** Wrong for the shipped binary, as above.

## Evidence

- Upstream source at 393ed43 (v2.0.0, 2026-11-26): `src/cli.rs`,
  `src/commands/convert.rs`, `docs/`.
- `nix run nixpkgs#tack -- --help` on 2026-11-26: store path `tack-1.0.0`,
  `--version` prints `tack 0.1.1`, nine commands.
- This repo: 43 direct inputs, 112 lock nodes, and a nightly update job,
  update-policy, the pins registry and flake-checker all read `flake.lock`.

## Revisit when

- nixpkgs ships tack 2.x: drop the version gate, or flip its default.
- tack adds a command that lets non-tack consumers override inputs: drop
  that "stay on flake.lock" condition.
- This repo adopts tack: rewrite its `AGENTS.md` note and the pins skill.
