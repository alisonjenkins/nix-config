# Nix

## Repo shape
- This flake uses the **dendritic pattern**: flake-parts + haumea. Files under
  `flake-modules/` are auto-discovered — adding a file is enough, there is no
  central import list to update.
- Modules follow the options pattern: `options.<name>` plus
  `config = lib.mkIf cfg.enable { ... }`.
- Cross-file references go through flake outputs (`self.nixosModules.*`,
  `self.homeModules.*`) and `self + "/path"`. **Never** relative imports
  (`../../`).

## Rules
- **DRY is enforced.** A value used twice (SSH keys, hostnames, ports, mandate
  text) gets one definition and is referenced. Duplicated literals are a bug.
- New or renamed files must be `git add`ed before building — flakes only see
  tracked files, and the failure looks like "file does not exist".
- `symlinkJoin` merges directory *contents*. To keep each input as its own
  named directory, use `linkFarm`. Mixing these up silently flattens trees.
- Avoid IFD. Prefer `source`-linked store paths over `builtins.readFile` into
  a text option when the thing is a whole directory.
- Overlays here take only `{ inputs }` and branch on
  `final.stdenv.hostPlatform.system`.

## Build loop
`just build` (no activation) → `just test` (temporary) → `just switch`
(permanent) → `just deploy` (remote, deploy-rs). See the `infra` skill's
`nix.md` for the deployment side and the repo's `nix-config-workflows` skill
for host/module/secret scaffolding.
