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
  Before writing any literal — an SSH key, IP, DNS name, hostname, git URL,
  password hash — grep the flake for it. If it already exists, extract the
  existing occurrence into a shared file or a `flake.lib.<topic>` output and
  consume it from both places. Do not add the second copy.
- **Machine-specific settings go in the host's own configuration**, never in a
  shared module. `modules/base` and friends apply to desktops, laptops and
  servers alike; a core-count limit, kernel parameter, or hardware workaround
  that suits one machine is wrong for the others. Ask which hosts a setting
  should apply to before putting it somewhere shared.
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
