# Changelog - Create: Arkana + Aeronautics Client

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
