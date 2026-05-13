---
id: CLAUDE
aliases:
  - CLAUDE.md
tags: []
---
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS and nix-darwin flake configuration managing multiple machines including desktops, laptops (Framework and work), servers (storage, K8s, VPN gateway, KVM hypervisor), and macOS systems. The configuration uses home-manager for user-level configuration and supports both NixOS and Darwin systems.

## Common Commands

### Building and Switching

All commands are managed via `just` (justfile). The system automatically uses `nh` if available, otherwise falls back to `nixos-rebuild` or `darwin-rebuild`:

```bash
# Build and switch immediately
just switch [extraargs]
just s  # alias

# Build and set for next boot
just boot
just b  # alias

# Build without activating
just build [hostname] [extraargs]
just B  # alias

# Test temporarily (reverts on reboot)
just test [extraargs]
just t  # alias

# Update flake inputs
just update
just u  # alias

# Deploy to remote machines via deploy-rs
just deploy [extraargs]

# Build VM for testing
just test-build <hostname>

# Run built VM
just test-run <hostname>

# Build NixOS AMI image
just ami-build <hostname>

# Upload built AMI to AWS
just ami-upload <hostname> [region] [bucket]

# Build + upload AMI in one step
just ami <hostname> [region] [bucket]
```

### Common NixOS Operations

```bash
# Build specific host configuration
nix build ".#nixosConfigurations.<hostname>.config.system.build.toplevel"

# Check flake
nix flake check

# Show flake outputs
nix flake show

# Update specific input
nix flake lock --update-input <input-name>
```

## Architecture

This repository uses the **Dendritic Pattern** with **flake-parts** + **haumea** for modular, auto-discovered configuration.

### Directory Structure

- **`flake.nix`**: Minimal entry point (~50 lines of outputs logic). Defines inputs, uses haumea to auto-discover all flake-parts modules from `flake-modules/`.
- **`flake-modules/`**: All flake output definitions, auto-discovered by haumea:
  - `overlays.nix`: Exports `flake.overlays` from `overlays/`
  - `deploy.nix`: deploy-rs node definitions and checks
  - `dev-shells.nix`: Development shell (`perSystem.devShells.default`)
  - `templates.nix`: Flake templates
  - `nixos-modules.nix`: Exports all NixOS modules as `flake.nixosModules.*`
  - `home-modules.nix`: Exports home-manager modules as `flake.homeModules.*`
  - `hosts/`: One **directory** per host configuration (NixOS, Darwin, standalone home-manager), each containing `default.nix` (the flake-parts module), `hardware-configuration.nix` (wrapped as `flake.nixosModules.<hostname>-hardware`), and `disko-config.nix` (wrapped as `flake.nixosModules.<hostname>-disko-config`)
- **`modules/`**: Reusable NixOS modules using the **options system** (`options.*` / `config = mkIf cfg.enable`):
  - `base/`: Core system configuration (networking, boot, nix settings, impermanence, secure boot)
  - `desktop/`: Desktop environment configurations
  - `development/`: Development tools and environments (e.g., web development)
  - `locale/`: Localization settings
  - `libvirtd/`, `vr/`, `rocm/`, `ollama/`, `servers/`: Specialized functionality modules
  - `desktop-base/`, `desktop-1password/`, `desktop-aws-tools/`, `desktop-kubernetes/`, etc.: Desktop feature modules
  - `desktop-greetd/`, `desktop-greetd-regreet/`, `desktop-sddm/`: Display manager modules
  - `desktop-wm-plasma6/`, `desktop-wm-sway/`: Window manager modules
  - `hardware-fingerprint/`, `hardware-touchpad/`: Hardware feature modules
  - `k8s-master/`, `storage-server/`: Server role modules
- **`home/`**: Home-manager configurations:
  - `home-linux.nix`, `home-macos.nix`, `home-common.nix`: Platform-specific and shared configs
  - `programs/`: Per-program home-manager configurations (zsh, neovim, tmux, git, etc.)
  - `wms/`: Window manager configurations (river, plasma, etc.)
- **`pkgs/`**: Custom packages and overrides
- **`overlays/`**: System-independent nixpkgs overlays (accepts only `{ inputs }`, uses `final.stdenv.hostPlatform.system` internally)
- **`secrets/`**: SOPS-encrypted secrets (managed by sops-nix, configured in .sops.yaml)
- **`templates/`**: Flake templates (e.g., Rust development environment)

### Configuration Pattern

Each host is defined in its own flake-parts module directory at `flake-modules/hosts/<hostname>/`. These directories contain:

1. `default.nix`: The flake-parts module defining `flake.nixosConfigurations.<hostname>` (or `darwinConfigurations`/`homeConfigurations`)
2. `hardware-configuration.nix`: Wrapped as a flake-parts module exporting `flake.nixosModules.<hostname>-hardware`
3. `disko-config.nix`: Wrapped as a flake-parts module exporting `flake.nixosModules.<hostname>-disko-config`

All custom modules are referenced via `self.nixosModules.*` (exported in `nixos-modules.nix`) and enabled with `modules.<name>.enable = true`. Home-manager modules are referenced via `self.homeModules.*` (exported in `home-modules.nix`). File paths for secrets/patches use `self + "/path/to/file"`. No relative path imports (`../../`) are used — everything goes through flake outputs.

New flake-modules files are **auto-discovered** by haumea - just create a `.nix` file or directory in `flake-modules/` and it will be imported automatically.

The `modules/base` module uses NixOS options under `modules.base`:
- `enable`: Enable the base module
- `bootLoader`: Boot loader selection — enum of `"systemd-boot"`, `"grub"`, or `"secure-boot"` (Lanzaboote with TPM)
- `pcr15Value`: TPM PCR15 value for LUKS unlocking (required when `bootLoader = "secure-boot"`)
- `enableImpermanence`: Enable tmpfs root with persistence
- `impermanencePersistencePath`: Where to persist data (default: `/persistence`)
- `enableCachyOSKernel`: Enable CachyOS kernel overlay (for hosts using CachyOS kernel packages)
- `enableOpenSSH`, `enableTailscale`, `enableIPv6`, `enableICMPPing`: Feature toggles
- `suspendState`: Suspend state (`"mem"`, `"standby"`, `"freeze"`, or `null` for auto-detect)
- `hibernateMode`: Hibernate mode (`"platform"` or `"shutdown"`)
- `timezone`, `consoleKeyMap`: Locale settings
- `beesdFilesystems`: Btrfs dedup filesystem configuration

### Key Systems

**Overlays**: The flake provides system-independent overlays for accessing different nixpkgs channels:
- `pkgs.stable`: nixpkgs 25.11 stable
- `pkgs.unstable`: nixos-unstable
- `pkgs.master`: nixpkgs master branch

Configured in `overlays/default.nix` and exported via `flake-modules/overlays.nix`. Applied per-host in their flake-parts module files.

**Impermanence**: Several hosts use tmpfs root filesystems with selective persistence via the impermanence module. Persistence paths are configured per-host.

**Secrets Management**: Uses sops-nix with age encryption. Age keys are defined in `.sops.yaml` with path-based rules for different hosts/secrets.

**Remote Deployment**: The flake exports a `deploy` attribute using deploy-rs for remote system deployments, defined in `flake-modules/deploy.nix`.

### Active Hosts

Key configurations defined in the flake:
- **Desktop/Laptop**: `ali-desktop`, `ali-framework-laptop`, `ali-work-laptop`
- **macOS**: `Alisons-MacBook-Pro` (Darwin configuration for work laptop)
- **Servers**: `home-storage-server-1`, `home-kvm-hypervisor-1`, `home-k8s-master-1`, `home-k8s-server-1`, `home-vpn-gateway-1`, `download-server-1`
- **Dev/Test**: `dev-vm` (aarch64-linux VM)
- **Home-Manager Only**: `ali` (Arch Linux), `deck` (Steam Deck)

### Notable Flake Inputs

- `ali-neovim`: Custom Neovim configuration flake
- `home-manager`: User environment management
- `stylix`: System-wide theming
- `plasma-manager`: KDE Plasma home-manager integration
- `sops-nix`: Secrets management
- `disko`: Declarative disk partitioning
- `lanzaboote`: Secure Boot support
- `impermanence`: Tmpfs root persistence
- `deploy-rs`: Remote deployment tool
- `nixos-hardware`: Hardware-specific configurations (e.g., Framework 16)
- `nixos-cosmic`: Alternative desktop environment
- `rust-overlay`: Rust toolchain management
- `jovian-nixos`: Steam Deck specific configurations
- `niks3`: Self-hosted binary cache push tool

### CI/CD Workflows

- **`build-and-cache.yaml`**: Builds all nixosConfigurations on push to main and pushes to niks3 binary cache. Includes dry-run check to skip cached builds and parallel build+push via queue drain.
- **`update.yaml`**: Automated daily flake lock updates (2 AM UTC)
- **`ami-build-and-upload.yaml`**: Builds and uploads NixOS AMIs to AWS with retention cleanup
- **`closure-report.yaml`**: Generates closure size reports for desktop/laptop configurations

### Minecraft modpack server packaging

Two patterns ship Minecraft modpacks as Nix-built OCI images:

- `pkgs/create-sky-colonies-server` — vanilla pattern. The publisher releases a "Server Pack" zip; we `fetchurl` it and overlay perf mods + JVM args + entrypoint. Used for any modpack whose publisher ships a pre-installed server tree.
- `pkgs/create-arkana-aeronautics-server` — manifest-driven pattern with bisection. Modpack ships only a CurseForge "manifest pack" (manifest.json + overrides/, no jars), so we resolve every mod via cfwidget+mediafilez into `arkana-mods.nix`, run the NeoForge installer at first boot to populate `/data/libraries`, and bisect mod groups to find what coexists.

The bisection workflow is the part worth knowing. `pkgs/minecraft-modpack-tools` ships generic helpers (`dep-tree` is the only one currently); `pkgs/create-arkana-aeronautics-server` keeps the modpack-specific pieces (`group-classifier.py`, `bisect.sh`, `generate-arkana-mods.sh`).

#### When to bisect

Whenever a modpack's overlay (extra mods we add on top) requires a Create / NeoForge / library version newer than what the base modpack ships. Bumping a single core lib often cascades into mod-construction or registry-init NPEs across 5-15 unrelated mods that were tuned to the older API. Bisecting identifies which Arkana mods stay compatible with the bumped floor — keep those, disable the rest.

#### The four files that drive composition

- `arkana-mods.nix` — auto-generated from the modpack's manifest.json. **Don't hand-edit.** Regenerate with `generate-arkana-mods.sh /path/to/manifest.json arkana-mods.nix` after a modpack version bump.
- `arkana-mods-extras.nix` — three lists:
  - `replacements` — newer file-IDs swapped for entries in `arkana-mods.nix` whose Arkana version is incompatible with our bumped floor. Set `alwaysInclude = true` for replacements that are part of the floor itself (Create 6.0.10 is the only one today). Replacements without `alwaysInclude` only apply when their `origProjectID`'s group is enabled.
  - `skipped` — discontinued mods with no live file on CurseForge. Always dropped server-side; client zip strips manifest entries so the launcher doesn't error on import.
  - `disabled` — mods that boot-fail under our bumped floor. Always dropped, even when their group is enabled. Includes a `reason` and `phase` field for the next person debugging.
- `arkana-groups.nix` — auto-classified by `group-classifier.py` from arkana-mods.nix filenames. Pure regex pattern matching; hand-tweak the classifier rules when bisect surfaces a misclassified mod (e.g. `gtbcs_spell_lib` originally landed in `core-libs` but hard-deps `irons_spellbooks` so it moved to `irons-spells`).
- `overlays.nix` — Aeronautics + Sable + companions + library mods we add on top of Arkana. Each entry can carry `requiresGroup = "<name>"` so libraries (e.g. AeroBlender needs the `world` group's aether + terrablender) only ship when their dependents would actually load.

#### The bisect loop

```bash
# 1. Boot the floor (no Arkana groups). Should always pass.
./pkgs/create-arkana-aeronautics-server/bisect.sh

# 2. Pre-flight dep check on the floor + every Arkana group together.
nix build --impure --expr '
  let f = builtins.getFlake "."; sys = "aarch64-linux";
      pkgs = import f.inputs.nixpkgs { system = sys; config.allowUnfree = true; overlays = builtins.attrValues f.outputs.overlays; };
  in pkgs.create-arkana-aeronautics-server.override {
       enabledArkanaGroups = [ "core-libs" "apothic" "irons-spells" ... ];
     }'
# Build is gated by an installPhase dep-tree check — fails before docker
# layering if any required dep is missing or out-of-version-range. Surfaces
# blockers in seconds, not multi-minute boot cycles.
nix run .#dep-tree -- /nix/store/<server-tree-path>

# 3. Boot whatever passes (1) above.
./pkgs/create-arkana-aeronautics-server/bisect.sh core-libs apothic ...
# Watches docker logs for "Done (Xs)" or any FATAL/Failed-to-load line and
# dumps the latest crash report on failure.

# 4. For each FATAL surfaced: add the offender + its hard-dependents to
#    `disabled = [ ... ]` in arkana-mods-extras.nix, with a reason + phase.
#    Use `dep-tree --dependents <modId>` to find what cascades.
#    Re-run (3). Repeat.
```

Optimizations baked in: bisect.sh keeps `/data/libraries` between rounds (`FRESH=1` to wipe), server.properties pins `level-type=minecraft\:flat` (~10s saved per round on spawn-prepare), installPhase fails fast on dep-graph regressions.

#### Mod-version bumping (after the pack boots clean)

`pkgs/minecraft-modpack-tools/find-mod-bumps.py` walks the dep graph leaf-first, queries cfwidget + Modrinth for each mod's newest 1.21.1/NeoForge build, downloads candidates, and verifies forward + reverse `versionRange` compat. Emits ready-to-paste `replacements` blocks for `arkana-mods-extras.nix` with `$(nix hash file ...)` placeholders.

Run against the **built** server tree's `mods/`:

```bash
# Export mods from the OCI image
docker run --rm -v /tmp/mods:/out --entrypoint /bin/sh \
  ghcr.io/<user>/create-arkana-aeronautics-server:<tag> \
  -c 'mkdir -p /out/mods && cp -L /opt/server/mods/*.jar /out/mods/'

python3 pkgs/minecraft-modpack-tools/find-mod-bumps.py /tmp
```

**Caveats — the tool's check is permissive:**
- Forward/reverse uses declared `mods.toml` `versionRange` only. Mods commonly declare open ranges (`[0.10,)`); these admit any newer lib on paper but the dependent's bytecode may reference classes the new lib removed → runtime `NoClassDefFoundError` / `MixinTransformerError`. **Always boot-test after applying bumps.**
- Tool prints `no compatible newer version found` for a dependent when its newer published versions declare a lib `versionRange` excluding the current lib version. That's the **lockstep bump signal** — bump lib + dependent together. Confirmed safe bundles: sophisticated-family (core + storage + backpacks + 2 create-integrations), familiarslib 1.7 + alshanex_familiars v4, irons_spellbooks family (spellbooks + jewelry + gtbcs_spell_lib + aces_spell_utils).
- Known-bad ABI bumps (will drop mods): `relics 0.12.4` removes `IRelicItem`/`IRenderableCurio`/`ExperienceAddEvent` used by arcane_abilities, reliquified_lenders_cataclysm, reliquified_ars_nouveau; `azurelib 3.1.8` moves `AzureLib` class used by crystal_chronicles, cataclysm_spellbooks; `twilightforest 4.8` MixinTransformerError; `moonlight 3.0.7` major.
- **Ignore NeoForge in-game `OUTDATED` reports.** NF string-compares `version=` against Modrinth's `forge_updates.json` `promos` which auto-publishes versions with `+mod` / `+mc1.21.1` metadata suffixes. Use `find-mod-bumps` for ground truth.
- `lionfishapi 2.7-fix-fix` drops `IAnimatedEntity` — `arkana-mods-extras.nix` pins 2.6. Comment in extras explains; don't bump.
- cfwidget's fileID sort isn't strictly version-sorted; watch for downgrades (`jeresources 1.6.0.17 → .12`).

**Shipping a bump round:**
1. Apply bumps to `arkana-mods-extras.nix`. Dedupe by `projectID` (one entry per mod); preserve original arkana `origFileID` when overwriting an earlier replacement.
2. New mods (not in `arkana-mods.nix`) go into `overlays.nix` via the `curseforge` or `modrinth` helper.
3. `nix build .#minecraft-arkana-aeronautics-image` → `docker load < <path>` → fresh container, watch for `Done (Xs)` and `failed to load correctly`.
4. If broken: pull crash report from logs, identify failing mod, revert that bump, rebuild. Bisect by removing bumps in groups if multiple fail.
5. Commit + annotated tag `arkana-aeronautics-v<modpack-version>-<n>`. GHA workflow only fires on tag push.
6. Update gitops `clusters/aws-k3s/flux-system/minecraft/deployment.yaml` image tag separately to roll the deployed server.

#### Known issue: OpenLoader datapack path

`entrypoint.sh` symlinks `/data/openloader/data/` → `/opt/server/openloader/data/` for the OpenLoader mod to pick up shipped datapacks (move-spawners, rare-pixie-villages, ensure-vanilla-tags). **OpenLoader 21.1.5 actually scans `/data/config/openloader/packs/` instead** — the old path is ignored. Server-side datapacks silently don't load. Confirmed via `docker logs` showing `[Open Loader/]: Located 0 packs.`. Fix pending: symlink to the new path or write `/data/config/openloader/options.json` with `additional_locations: ["openloader/data"]` from the entrypoint.

#### Crash-pattern triage

| Signature | Phase | Likely fix |
|---|---|---|
| `Mod X requires Y N.N or above` | dep-resolution | bump in `replacements`, or move Y into an enabled group |
| `Attempted to load class net/minecraft/client/...` | class-load | mod is client-only; add to `clientOnlyProjectIDs` in `default.nix` |
| `failed injection check, (0/N) succeeded` mixin | mod-construction | mod's mixin targets removed/renamed API on the bumped Create / NeoForge — bump the mod or `disabled` it |
| `Trying to access unbound value: ResourceKey[...]` | registry-init | `DeferredHolder` resolved before its registry runs; usually a mod's mixin firing during another mod's RegisterEvent. Hard to fix without bumping the mixin source — usually `disabled` |
| `Cannot get config value before config is loaded` | common-setup | mod calls config.get from FMLCommonSetupEvent; NeoForge 21.1.x lifecycle incompatibility — `disabled` |

### Pending: niks3 cache push on desktops/laptops

The `modules/niks3-cache-push` module and GHA parallel push workflow are implemented but **not yet enabled** on hosts. To finish:

1. Create `secrets/niks3-token.enc.yaml` via `sops secrets/niks3-token.enc.yaml` with key `niks3_token`
2. Add ali-framework-laptop's server age key to `.sops.yaml` (keys section + niks3-token creation rule)
3. Uncomment the `modules.niks3CachePush` and `sops.secrets.niks3-token` blocks in:
   - `flake-modules/hosts/ali-desktop/default.nix`
   - `flake-modules/hosts/ali-framework-laptop/default.nix`
   - `flake-modules/hosts/ali-work-laptop/default.nix`

## Development Workflow

When modifying configurations:
1. Edit relevant files in `modules/`, `home/`, or `flake-modules/hosts/<hostname>/`
2. Test changes with `just test` for temporary activation
3. Use `just build` to build without activating (useful for checking for errors)
4. Commit with `just switch` to activate and make permanent
5. For remote hosts, use `just deploy .#<hostname>` after testing locally

When adding new hosts:
1. Create a directory at `flake-modules/hosts/<hostname>/` (auto-discovered by haumea)
2. Create `default.nix` as a flake-parts module defining `flake.nixosConfigurations.<hostname>`
3. Create `hardware-configuration.nix` wrapped as `{ ... }: { flake.nixosModules.<hostname>-hardware = { ... }; }`
4. Create `disko-config.nix` wrapped as `{ ... }: { flake.nixosModules.<hostname>-disko-config = { ... }; }`
5. Reference custom modules via `self.nixosModules.*`, home modules via `self.homeModules.*`, secrets via `self + "/secrets/..."`, and overlays via `self.overlays.*`
6. New files must be `git add`ed before `nix eval`/`nix build` will see them (flake git tracking)

When adding new NixOS modules (two-step process):
1. Create the module in `modules/<name>/default.nix` using the options pattern
2. Export it in `flake-modules/nixos-modules.nix` (add an entry to `flake.nixosModules`)
3. Reference it in host files via `self.nixosModules.<name>`
4. New files in `modules/` must be `git add`ed before `nix eval`/`nix build` will see them (flake git tracking)

When adding new flake-modules:
1. Create a `.nix` file in `flake-modules/` or `flake-modules/hosts/`
2. The file will be auto-discovered by haumea - no need to update `flake.nix`
3. Use the flake-parts module signature: `{ inputs, self, ... }: { flake = { ... }; }`

When adding secrets:
1. Add age keys to `.sops.yaml` if needed
2. Create secret files in `secrets/` or `secrets/<hostname>/`
3. Unencrypted Secrets should be named using the pattern `<name>.dec.yaml` so that they are gitignored. Encrypted secrets get saved with the name pattern `<name>.enc.yaml`
4. Encrypt with `sops` command
5. Reference in host configuration via `sops.secrets.<name>`
