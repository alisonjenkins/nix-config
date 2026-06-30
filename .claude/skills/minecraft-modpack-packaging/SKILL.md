---
name: minecraft-modpack-packaging
description: How this repo packages Minecraft modpacks as Nix-built OCI images
  (create-sky-colonies-server vanilla pattern, create-arkana-aeronautics-server
  manifest+bisection pattern). Use when working on pkgs/create-*-server,
  pkgs/minecraft-modpack-tools, the bisect loop, mod-version bumping
  (find-mod-bumps), arkana-mods*.nix / arkana-groups.nix / overlays.nix, dep-tree,
  CurseForge/NeoForge/Create version floors, or any Minecraft modpack server crash
  triage in this repo.
---

# Minecraft modpack server packaging

Two patterns ship Minecraft modpacks as Nix-built OCI images:

- `pkgs/create-sky-colonies-server` — vanilla pattern. The publisher releases a "Server Pack" zip; we `fetchurl` it and overlay perf mods + JVM args + entrypoint. Used for any modpack whose publisher ships a pre-installed server tree.
- `pkgs/create-arkana-aeronautics-server` — manifest-driven pattern with bisection. Modpack ships only a CurseForge "manifest pack" (manifest.json + overrides/, no jars), so we resolve every mod via cfwidget+mediafilez into `arkana-mods.nix`, run the NeoForge installer at first boot to populate `/data/libraries`, and bisect mod groups to find what coexists.

The bisection workflow is the part worth knowing. `pkgs/minecraft-modpack-tools` ships generic helpers (`dep-tree` is the only one currently); `pkgs/create-arkana-aeronautics-server` keeps the modpack-specific pieces (`group-classifier.py`, `bisect.sh`, `generate-arkana-mods.sh`).

## When to bisect

Whenever a modpack's overlay (extra mods we add on top) requires a Create / NeoForge / library version newer than what the base modpack ships. Bumping a single core lib often cascades into mod-construction or registry-init NPEs across 5-15 unrelated mods that were tuned to the older API. Bisecting identifies which Arkana mods stay compatible with the bumped floor — keep those, disable the rest.

## The four files that drive composition

- `arkana-mods.nix` — auto-generated from the modpack's manifest.json. **Don't hand-edit.** Regenerate with `generate-arkana-mods.sh /path/to/manifest.json arkana-mods.nix` after a modpack version bump.
- `arkana-mods-extras.nix` — three lists:
  - `replacements` — newer file-IDs swapped for entries in `arkana-mods.nix` whose Arkana version is incompatible with our bumped floor. Set `alwaysInclude = true` for replacements that are part of the floor itself (Create 6.0.10 is the only one today). Replacements without `alwaysInclude` only apply when their `origProjectID`'s group is enabled.
  - `skipped` — discontinued mods with no live file on CurseForge. Always dropped server-side; client zip strips manifest entries so the launcher doesn't error on import.
  - `disabled` — mods that boot-fail under our bumped floor. Always dropped, even when their group is enabled. Includes a `reason` and `phase` field for the next person debugging.
- `arkana-groups.nix` — auto-classified by `group-classifier.py` from arkana-mods.nix filenames. Pure regex pattern matching; hand-tweak the classifier rules when bisect surfaces a misclassified mod (e.g. `gtbcs_spell_lib` originally landed in `core-libs` but hard-deps `irons_spellbooks` so it moved to `irons-spells`).
- `overlays.nix` — Aeronautics + Sable + companions + library mods we add on top of Arkana. Each entry can carry `requiresGroup = "<name>"` so libraries (e.g. AeroBlender needs the `world` group's aether + terrablender) only ship when their dependents would actually load.

## The bisect loop

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

## Mod-version bumping (after the pack boots clean)

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

## Known issue: OpenLoader datapack path

`entrypoint.sh` symlinks `/data/openloader/data/` → `/opt/server/openloader/data/` for the OpenLoader mod to pick up shipped datapacks (move-spawners, rare-pixie-villages, ensure-vanilla-tags). **OpenLoader 21.1.5 actually scans `/data/config/openloader/packs/` instead** — the old path is ignored. Server-side datapacks silently don't load. Confirmed via `docker logs` showing `[Open Loader/]: Located 0 packs.`. Fix pending: symlink to the new path or write `/data/config/openloader/options.json` with `additional_locations: ["openloader/data"]` from the entrypoint.

## Crash-pattern triage

| Signature | Phase | Likely fix |
|---|---|---|
| `Mod X requires Y N.N or above` | dep-resolution | bump in `replacements`, or move Y into an enabled group |
| `Attempted to load class net/minecraft/client/...` | class-load | mod is client-only; add to `clientOnlyProjectIDs` in `default.nix` |
| `failed injection check, (0/N) succeeded` mixin | mod-construction | mod's mixin targets removed/renamed API on the bumped Create / NeoForge — bump the mod or `disabled` it |
| `Trying to access unbound value: ResourceKey[...]` | registry-init | `DeferredHolder` resolved before its registry runs; usually a mod's mixin firing during another mod's RegisterEvent. Hard to fix without bumping the mixin source — usually `disabled` |
| `Cannot get config value before config is loaded` | common-setup | mod calls config.get from FMLCommonSetupEvent; NeoForge 21.1.x lifecycle incompatibility — `disabled` |
