---
name: nix-config-workflows
description: How to modify and build this nix-config repo — editing configs, adding hosts, NixOS modules, flake-modules, and secrets. Use when adding a new host / module / flake-module / secret, or when unsure of the test→build→switch→deploy flow. Covers haumea auto-discovery and the git-add-before-build gotcha.
---

# nix-config workflows

## Modify configs
1. Edit `modules/`, `home/`, or `flake-modules/hosts/<hostname>/`
2. `just test` — temporary activation (reverts on reboot)
3. `just build` — build without activating (error check)
4. `just switch` — activate + permanent
5. Remote hosts: `just deploy .#<hostname>` after local test

## Add new host
1. Create dir `flake-modules/hosts/<hostname>/` (haumea auto-discovers)
2. `default.nix` — flake-parts module defining `flake.nixosConfigurations.<hostname>` (or `darwinConfigurations`/`homeConfigurations`)
3. `hardware-configuration.nix` wrapped: `{ ... }: { flake.nixosModules.<hostname>-hardware = { ... }; }`
4. `disko-config.nix` wrapped: `{ ... }: { flake.nixosModules.<hostname>-disko-config = { ... }; }`
5. Reference: custom modules `self.nixosModules.*`, home `self.homeModules.*`, secrets `self + "/secrets/..."`, overlays `self.overlays.*`
6. `git add` new files before `nix eval`/`nix build` sees them (flake git tracking)

## Add new NixOS module (2-step)
1. Create `modules/<name>/default.nix` (options pattern: `options.*` / `config = mkIf cfg.enable`)
2. Export in `flake-modules/nixos-modules.nix` (add to `flake.nixosModules`)
3. Reference in hosts via `self.nixosModules.<name>`, enable `modules.<name>.enable = true`
4. `git add` new `modules/` files before build

## Add new flake-module
1. Create `.nix` in `flake-modules/` or `flake-modules/hosts/`
2. Auto-discovered by haumea — no `flake.nix` edit
3. Signature: `{ inputs, self, ... }: { flake = { ... }; }`

## Add secrets
1. Add age keys to `.sops.yaml` if needed
2. Create in `secrets/` or `secrets/<hostname>/`
3. Naming: unencrypted `<name>.dec.yaml` (gitignored); encrypted `<name>.enc.yaml`
4. Encrypt with `sops`
5. Reference via `sops.secrets.<name>`
