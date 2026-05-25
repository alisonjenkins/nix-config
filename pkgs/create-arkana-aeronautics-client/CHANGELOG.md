# Changelog - Create: Arkana + Aeronautics Client

## [v1.5-aero-1.2.1-56] - 2026-05-25

### Summary

Round 4 of `find-mod-bumps`: 24 mod bumps applied after a Rust-port of
the bump tool added parallel HTTP + a fixpoint pass that catches
consumer-bumps gated on a lib bump in the same round. Two visible
keymap collisions fixed in the client. Two flagged bumps (relics,
lionfishapi) deliberately skipped — bytecode scan confirmed they would
break mods that don't have a forward-compatible release available.

### Added — mod bumps

Inserted (no prior replacement) — five mods now pinned ahead of the
arkana base:
- **azurelib** 3.0.27 → **3.1.8** — package layout reorganised
  (`mod/azure/azurelib/common/api/` removed). Consumers
  cataclysm_spellbooks, hazennstuff and crystal_chronicles all bumped
  in lockstep to versions that moved to the new namespace; verified by
  classfile scan of the cached jars.
- **cataclysm** 3.16 → **3.28**
- **cataclysm_spellbooks** 1.1.9 → **1.1.10**
- **crystal_chronicles** 0.0.7-alpha → **0.0.9** — picked up by the
  fixpoint pass; declares `azurelib [3.1,)` which fails forward-check
  in leaves-first order alone.
- **hazennstuff** 1.2.0 → **1.4.0.10**

### Changed — mod bumps (in-place updates)

Existing replacement blocks rewritten:
- apothic_enchanting 1.5.2 → **1.5.3**
- create_dragons_plus 1.10.0 → **1.10.1**
- createultimine 1.3.1 → **1.3.2**
- ess_requiem 0.1.2 → **0.1.5**
- firesenderexpansion 2.3.5 → **2.4.0**
- ftbchunks 2101.1.13 → **2101.1.14**
- glassential 3.4.2 → **3.4.3**
- immersive_paintings 0.7.6 → **0.7.7**
- lithostitched 1.7.3 → **1.7.7**
- moonlight 3.0.7 → **3.0.14** — bytecode scan confirmed the removed
  `ConfigBuilderImpl$StringCodecConfigValue` / `$StringJsonConfigValue`
  inner classes have zero consumers in the pack; the old "moonlight
  3.0.7 major" note is now outdated.
- puzzleslib 21.1.39 → **21.1.46**
- sophisticatedbackpacks 3.25.45 → **3.25.49**
- sophisticatedcore 1.4.39 → **1.4.42**
- sophisticatedstorage 1.5.47 → **1.5.50**
- supplementaries 3.6.4 → **3.6.5**
- waystones 21.1.30 → **21.1.33**

Modrinth (overlays.nix):
- computercraft 1.118.0 → **1.119.0**
- tinyredstone 6.1.3 → **6.1.4**
- vivecraft 1.3.7 → **1.3.8**

### Removed — stale chain-replacement blocks

waystones and create_dragons_plus each had a second
chain-replacement block (`orig→A` plus `A→B`). Overwriting the first
block's new-fileID would have left the second one matching nothing,
causing the pack to install both copies of the mod side-by-side and
NeoForge to fail on duplicate modIds. Collapsed each to a single
canonical replacement that bumps directly from the arkana base.

### Skipped — flagged unsafe after bytecode investigation

- **relics 0.10.7.6 → 0.12.7** — IRelicItem still exists in 0.12.7,
  but `IRenderableCurio` and `ExperienceAddEvent` are gone.
  arcane_abilities 0.2.8 (latest) references `ExperienceAddEvent`;
  reliquified_twilight_forest 0.5.3 (latest) uses `IRenderableCurio`.
  No forward-compatible releases exist for either, so the bump would
  break two mods unconditionally.
- **lionfishapi 2.7-fix-fix → 3.0-beta** — drops `IAnimatedEntity`,
  which IceAndFireCE, cataclysm (including the bumped 3.28), alltheleaks
  and uranus all reference via bytecode. No forward-compatible release
  available for the consumers.

### Fixed — client keymaps

- **`I` key no longer steals focus from modded UIs**.
  Aether's "Open/Close Accessories Inventory"
  (`key.aether.open_accessories.desc`) defaulted to `I`. Typing the
  letter `I` in any focused modded search field (Ars Magicka storage
  search, Create filter slots, JEI input) fired the hotkey, opened
  Aether's accessories screen, and closed the modal UI. Pre-bind to
  `key.keyboard.unknown` in `overrides/options.txt`. Players can pick
  a different key in Options → Controls if they actually use Aether's
  accessory tab.
- **Relics HUD toggle off `LEFT_ALT`**.
  `key.relics.active_abilities_list` defaulted to `LEFT_ALT`, the same
  modifier Create uses for schematic positioning. Held LEFT_ALT while
  placing a schematic flipped the Relics HUD instead of moving the
  schematic ghost. Re-bound to `'` (apostrophe) — vanilla-unbound and
  not registered by any other mod in the pack (verified via per-jar
  KeyMapping disassembly).

**Existing players whose `options.txt` was already written by a prior
launch must rebind these themselves** in Options → Controls — the
modpack-shipped values apply on first launch only, then MC owns the
file.

### Tooling

- `pkgs/minecraft-modpack-tools/find-mod-bumps` rewritten in Rust.
  Parallel cfwidget + Modrinth listing fetch, parallel per-mod
  candidate jar pre-download, HTTP wrapped in exponential-backoff
  retries (500ms → 30s cap, classifies transient 408/425/429/5xx vs
  terminal). Adds a fixpoint loop that re-evaluates mods initially
  skipped as "no compatible newer version found" against bumps
  committed in earlier passes — fixes a leaves-first false-negative
  where a consumer requiring a bumped lib's new version range was
  evaluated before the lib's bump was decided. 40 unit + integration
  tests; nix derivation builds via `rustPlatform.buildRustPackage`.

## [Unreleased] - 2026-05-14

### Summary

Root-causes a longstanding "released modpack didn't crash, but resource packs
silently weren't loading" bug. Fixes OpenLoader's empty-`additional_locations`
default so the bundled visual packs (Stay True / Fresh Animations / Create:
Fresh Items) actually apply on first launch — and patches the latent mod-side
crashes that surface once those packs are loaded for real.

### Fixed

1. **OpenLoader 21.1.5 auto-load broken** — `Located 0 packs` on every boot
   - **Cause**: stock `config/openloader/options.json` ships with
     `additional_locations: []`. OpenLoader only scans
     `config/openloader/packs/` by default — modpack puts packs in
     `openloader/resources/` and `openloader/data/` (the documented OL
     paths). Those trees were ignored on every launch.
   - **Fix**: ship `overrides/config/openloader/options.json` with
     `additional_locations: ["openloader/resources", "openloader/data"]`
     so OL discovers both directories before it writes its own default.
   - **Impact**: Stay True, Stay True Compats, Fresh Animations, Create:
     Fresh Items, and the new FA+ / Simply Swords Reforged packs all
     auto-apply on first launch with no manual toggling in Options →
     Resource Packs.
   - **Files**: new `openloader-options.json`; install step in `default.nix`.

2. **Supplementaries `compat.CompatEMFMixin` crash with EMF 3.x JEM packs**
   - **Cause**: supplementaries' compat mixin `@Inject`s into
     `EMFModelPartCustom` with the pre-3.0 EMF callback signature. EMF 3.x
     added an `EMFModelPartRoot` parameter to the callback. AllTheLeaks
     1.1.8 carries a runtime fix for the [3.0.0, 3.0.6) range only.
   - **Pre-fix**: in the released modpack this never triggered because
     OpenLoader was silently failing to load resource packs (see #1), so
     EMF never instantiated `EMFModelPartCustom` and the mixin never
     applied. Once #1 was fixed, model bake started crashing during the
     "Rendering overlay" phase.
   - **Fix**: build-time-patch `supplementaries-common.mixins.json` inside
     the supplementaries jar to remove `compat.CompatEMFMixin` from the
     `client[]` mixin list. Manifest entry for projectID 412082 stripped
     so the CurseForge launcher doesn't re-download an unpatched copy.
   - **Files**: new `strip-supplementaries-emf-mixin.py`; jar patched +
     dropped into `overrides/mods/` from `default.nix`.

### Added

3. **FreshAnimations + Extensions (FA+) auto-loaded resource pack**
   - **Why**: previously the v1.9 of this pack was being dropped into
     player `resourcepacks/` folders manually but it ships
     `min_format=84` (MC 1.21.6+) and crashes 1.21.1 with
     `JsonParseException: No key pack_format`. The pack was always
     marked Incompatible in the Options screen.
   - **Now**: v1.8.1 (last 1.21.1-supported release, `pack_format=15` +
     `supported_formats=15..999`) bundled into
     `overrides/openloader/resources/05-fa-all-extensions-1.8.1.zip`.
     Auto-loaded by OpenLoader after #1.
   - **Files**: `resource-packs.nix` entry.

4. **Simply Swords Reforged auto-loaded resource pack**
   - **Why**: 3D weapon-model overlay for the Simply Swords mod. Author
     forgot to widen `supported_formats` so the pack claims
     `pack_format=16` (MC 1.20.2) only and shows Incompatible on 1.21.1
     even though content is pure model/texture overrides.
   - **Now**: build-time-patch `pack.mcmeta` to advertise
     `supported_formats: {min_inclusive: 16, max_inclusive: 99}`, then
     ship as `overrides/openloader/resources/06-simply-swords-reforged-v1.zip`.
   - **Files**: new `patchMcmeta` helper in `resource-packs.nix`.

### Changed

5. **`resource-packs.nix` signature expanded**
   - **Before**: `{ fetchurl }:` — every entry had to be a plain
     `fetchurl`.
   - **After**: `{ fetchurl, stdenvNoCC, unzip, zip, jq }:` — entries can
     now reference build-time-patched derivations via the new
     `patchMcmeta { pname, version, src, minInclusive, maxInclusive }`
     helper.
   - **Impact**: clean place to land future packs that need their mcmeta
     widened, without ad-hoc patching in `default.nix`.

6. **Manifest filter renamed `stripJij` → `stripIds`**
   - **Why**: the projectID-strip list is no longer ars_nouveau-specific
     (was only stripping JIJ-bundled mods); it now also strips
     supplementaries so the launcher doesn't re-download the unpatched
     jar. Renamed for clarity.
   - **Impact**: cosmetic — same behaviour, broader use.

### Not changed (investigated, reverted)

- **`dynamic_difficulty 0.9.1 → 1.1.1+1.21.1`** — tried, reverted. 0.9.1
  was working fine in the released modpack; the apparent crash was
  caused by us bumping EMF (#7 below) which knocked out AllTheLeaks'
  patch range.
- **`entity_model_features 3.0.1 → 3.2.4`** — tried, reverted. 3.0.1 is
  inside AllTheLeaks' patch range `[3.0.0, 3.0.6)`; bumping out of range
  drops the runtime patch and surfaces other latent mod bugs.
- **`immersive_melodies 0.6.2 → 0.6.4`** — tried, reverted. 0.6.x all
  share the same `<clinit>` registry-register architecture; 0.6.4 isn't
  fixed in any meaningful way. Original 0.6.2 works because OL wasn't
  triggering its code path before #1.

### Known caveats

- Supplementaries' EMF skin-compat feature is now off. In practice this
  only affects mob skin overlays for the cosmetic-trinket subset of
  supplementaries content (rare). Vanilla mobs animated by Fresh
  Animations directly are unaffected — that compat path doesn't go
  through CompatEMFMixin.
- AllTheLeaks 1.1.8 remains the latest release available for 1.21.1
  NeoForge. EMF must stay in `[3.0.0, 3.0.6)` for its patches to apply;
  do not bump EMF past 3.0.5 without verifying ATL has been updated.

---

## Related — NixOS host fixes (separate commit)

Commit `d42d5f79` — `feat(framework-laptop/audio): fix gaming stutter via
governor + mlock + stereo profile` — touches `modules/power-management`,
`modules/desktop`, and `flake-modules/hosts/ali-framework-laptop`. Not
part of the modpack distribution. Summary:

- Per-AC-state `cpuFreqGovernor` + `energyPerformancePreference` options
  on `modules.powerManagement` (performance/performance on AC,
  powersave/balance_power on battery).
- `mem.mlock-all` extended to the `pipewire-pulse` context (was only on
  the `pipewire` daemon — pulse-compat process got paged out under
  memory pressure).
- New `modules.desktop.pipewire.forceStereoCards` option emitting a
  WirePlumber rule that pins matching cards to analog-stereo. Set for
  `alsa_card.pci-0000_c4_00.6` on `ali-framework-laptop` to stop the
  `surround40:2p follower resync` ALSA underrun storm.
