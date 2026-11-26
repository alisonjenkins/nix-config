# Working in a flake.lock repo

## Commands

| Goal | Command |
|---|---|
| Bump one input | `nix flake update NAME` |
| Bump everything | `nix flake update` |
| Lock new inputs without bumping others | `nix flake lock` |
| Try a different source without locking it | `--override-input NAME URL` on build/eval |
| Show the lock graph | `nix flake metadata` |

Old docs say `nix flake lock --update-input NAME`. Current Nix deprecates
it in favour of `nix flake update NAME`. Use whichever the installed Nix
accepts.

## Follows

Share one nixpkgs by declaring it per input:

```nix
inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
```

Nested inputs need their own lines. Count `nixpkgs` nodes in `flake.lock`
to find duplicates.

## Repo tooling comes first

Many repos wrap updates: a scheduled bot, a policy tool, a `just` recipe.
Look in `.github/workflows/`, `justfile`, `Makefile` and the repo's
`AGENTS.md` before running `nix flake update` by hand. Bumping past the
wrapper can skip its checks or fight its next run.

## Verify

1. `git diff flake.lock` shows only the inputs you meant to move.
2. Build or eval what changed.
3. Commit `flake.lock` alone, or with the `flake.nix` change that needed it.
