# Nix

## Repo shape
Flake layout varies a lot between repos — check what's actually there before
assuming a convention. Common patterns you'll run into:
- **Dendritic** (flake-parts + haumea, or similar): files under a modules
  directory are auto-discovered — adding a file is enough, no central import
  list. If the repo uses this, follow it; don't hand-roll an import list.
- **Explicit imports**: a central `default.nix`/`flake.nix` lists every
  module by path. Adding a file *does* require updating the list here.
- Modules commonly follow the options pattern: `options.<name>` plus
  `config = lib.mkIf cfg.enable { ... }` — but confirm the repo actually uses
  it before assuming.
- If the repo favors flake-output cross-references (`self.nixosModules.*`,
  `self + "/path"`) over relative imports (`../../`), match that; grep for the
  existing style rather than picking one.

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
- **A lambda default on a module argument does not make it optional.** Writing
  `{ someArg ? "fallback", ... }:` looks like it makes the argument safe to
  omit, and does not: the module system resolves named arguments through
  `_module.args` and never consults the default, failing with
  `error: attribute 'someArg' missing`. Every configuration importing the
  module must pass the value — so a module that is genuinely optional should
  read it as `args.someArg or "fallback"` from an `@ args` pattern instead.
  This bites when a module is shared between configurations that supply
  different argument sets, such as a NixOS host and a standalone
  home-manager configuration.
- Avoid IFD. Prefer `source`-linked store paths over `builtins.readFile` into
  a text option when the thing is a whole directory.
- Overlays here take only `{ inputs }` and branch on
  `final.stdenv.hostPlatform.system`.

## Build loop
Build (no activation) → temporary activation → permanent switch → remote
deploy, in increasing order of commitment. See the `infra` skill's `nix.md`
for the actual commands (own or repo-wrapped) and check for a project-local
workflow skill for host/module/secret scaffolding conventions.
