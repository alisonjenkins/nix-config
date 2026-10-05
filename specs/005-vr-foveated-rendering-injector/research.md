# Research: Foveated rendering for VR games that lack it

**Date**: 2026-10-05

Evidence labels: **Verified** (read in a primary source or measured on this machine),
**Partly verified** (read through a summarising fetch, so names and line numbers may be
approximate), **Inferred** (reasoning, no source). Anything inferred is turned into a spike in
`plan.md` before the work that depends on it.

## Decisions

### D1. Patch DXVK first; a Vulkan layer comes later, for Vulkan-native games only

- **Decision**: the D3D11 path is a patch carried as a fork of DXVK. A separate Vulkan
  implicit layer is a later phase for Vulkan-native games (Half-Life: Alyx).
- **Rationale**:
  - DXVK builds its pipelines from graphics pipeline libraries (partly verified: libraries for
    vertex input, pre-raster and fragment output). A layer would have to rewrite those create
    infos from outside; the fork edits them where they are built.
  - The fork can add the shading-rate dynamic state and the creation flag in the same place
    (inferred from where the libraries are built).
  - The one Linux precedent (`poprox24/dxvk-wivrn-gaze-vrs`) took the DXVK route.
- **Alternatives considered**:
  - A Vulkan layer for everything: rejected for D3D11 because of the pipeline-library rewrite
    above. Still the right shape for Vulkan-native games.
  - Reviving a Windows tool under Wine: rejected, since their foveation depends on Nvidia-only
    D3D11 extensions that DXVK does not expose (verified: DXVK has no shading-rate code).

### D2. What the fork must change in DXVK (partly verified, DXVK master 3.1.1)

- Enable `VK_KHR_fragment_shading_rate` and `attachmentFragmentShadingRate` where the device is
  created (`DxvkAdapter::createDevice`, `DxvkDeviceCapabilities`).
- Add `VK_DYNAMIC_STATE_FRAGMENT_SHADING_RATE_KHR` to the graphics pipeline dynamic state, and
  OR the rendering-attachment creation flag into the pipeline flags only while foveation is on,
  so the off path builds identical pipelines (supports SC-005).
- Chain `VkRenderingFragmentShadingRateAttachmentInfoKHR` into the draw render pass begin, and
  call the set-rate command once per matched pass with base rate 1x1 and combiners
  `{KEEP, REPLACE}` (measured as the minimum correct setup).
- Signals available to recognise the eye image at pass begin: framebuffer size, layer count,
  colour format and sample count. DXVK never sets a multiview view mask (verified: no `viewMask`
  in master), so a D3D11 instanced-stereo game appears as one target with 2 layers and no mask.

### D3. Rate image shape on this GPU (measured)

- 8x8-pixel tiles, `R8_UINT`, one layer (probe: layered rate images are unsupported), coarsest
  rate 2x2, 8x MSAA falls back to 1x1. Rate code is `(log2(w) << 2) | log2(h)`.
- The poprox24 patch uses 16x16 tiles and a 2-layer rate image, so it cannot run on this GPU
  unmodified. Reusable from it: the shared-memory reader with a sequence counter, the pass
  filter shape, the rate-image upload path and the environment knobs.

### D4. Open fact: layered, non-multiview targets

- The probe tested multiview (view mask, one layer rate image, identical rates in both views).
  DXVK's instanced-stereo case is different: 2 layers, no view mask. With
  `layeredShadingRateAttachments` false, the rate image must have one layer and is then used for
  every layer (inferred from the Vulkan rules; the VUID text was not read).
- **Resolution**: spike S1 extends the probe with this case. If it fails, fall back to
  per-draw rates for layered passes.

### D5. Delivery: a compat tool that carries the patched DXVK, gated by an environment variable

- **Decision**: build the patched DXVK from the fork (flake input, as with the niri fork),
  combine it with the Proton the user runs into a Steam compat tool, and enable foveation only
  when the game's launch options set `DXVK_FOVEATION`. Without the variable the patched DXVK
  behaves like stock.
- **Rationale**:
  - A Proton update replaces files copied into its install (partly verified), so copying DLLs
    in place is fragile.
  - The repo's runner updater manages `compatibilitytools.d` (verified,
    `modules/desktop/default.nix:997-1045`), so the tool must be a separate directory it does
    not touch.
  - The two steps (pick the tool, set the variable) give per-game opt-in.
- **Alternatives considered**: per-prefix DLL copies with a DLL override (survives Proton
  updates but can drift from Proton's own DXVK); replacing DLLs in the Proton install (wiped by
  updates; rejected). Both stay as fallbacks if spike S3 fails.
- **Open**: that a compat tool can layer a Proton with only the DXVK directory replaced is
  inferred. Spike S3 confirms it.
- **Open**: the DXVK base version. Master is 3.1.1; Proton 10.0-3 ships 2.6.2 and Proton
  Experimental ships 2.7.1 plus commits (partly verified). Spike S5 chooses the base that the
  user's runner uses, and keeps the patch small to ease rebasing.

### D6. Profiles reuse DXVK's own configuration file

- **Decision**: per-game profiles are entries in a DXVK config file, selected by
  `DXVK_CONFIG_FILE`, generated by a home-manager module. No new parser.
- **Rationale**: DXVK already reads a per-executable config (inferred, to be confirmed in S2).
  Reusing it keeps one mechanism (constitution V).
- **Alternative considered**: a separate JSON or TOML profile read by new code in DXVK. Rejected
  as extra parser code inside a third-party codebase.
- **Fast tuning loop**: the home module generates the default config, so changing it takes one
  home-manager switch. For quick iteration the owner sets `DXVK_CONFIG_FILE` to a scratch file
  in a single launch option, with no switch (FR-005).
- **Fallback if per-executable sections are not supported** (checked in spike S2): generate one
  config file per game and select it through `DXVK_CONFIG_FILE` in that game's launch option,
  instead of one shared file. FR-003's two-step enablement stays the same.

### D7. Measurement stack

- **Per-frame and per-pass GPU time**: timestamp queries inside the fork, written to a log.
  This is the only source that isolates the eye-image pass. MangoHud reports present-to-present
  time and a sampled busy percentage, so it is a cross-check only.
- **Power**: sample `/sys/class/hwmon/hwmon4/power1_average` (microwatts) at about 20 Hz and
  integrate. Verified on this machine: updates in under 100 ms, no readable averaging window.
  The integrated GPU is `hwmon5`; select the discrete card by PCI device `0x7550`, never by
  hwmon index.
- **Clocks**: `power_dpm_force_performance_level` is `auto` and writable only by root.
  Pinning it would reduce noise but raises power; offer it to the owner and do not run it.
  Record core clock per run and the active undervolt (-40 mV) with every result.
- **Statistics** (inferred, standard practice): 60 s warm-up discarded; at least 3,000 frames
  per run; 5 runs per condition, interleaved A B A B; per-run median frame time plus p99 and
  mean power from integrated energy; noise is the spread of per-run medians within a condition;
  a gain counts only when the difference exceeds twice the larger noise and has the same sign
  in every interleaved pair.

### D8. How to run a VR game repeatably without a person (risky, spike S4)

- Verified: SteamVR on Linux supports a null driver configured in
  `~/.local/share/Steam/config/steamvr.vrsettings` (`driver_null`, render size and refresh).
- Not verified for this work: whether Fallout 4 VR keeps rendering eye buffers on the null
  driver. One verified report shows an OpenXR session failing on Linux with the null driver;
  both target games use OpenVR, which may behave differently.
- **Fallback**: the Quest over Steam Link with a fixed pose. The stream encoder runs on the
  video engine, not the graphics queue, but its load must be noted.
- The repo already manages SteamVR settings and a null-HMD mode (`home/modules/vr/`), so the
  null-driver route can be tried without new modules.

### D9. Eye-image size is discovered, not hardcoded

- Nothing documents the per-eye target size or layout for Fallout 4 VR. Skyrim VR at 130%
  supersampling is reported at about 1724x1915 per eye (snippet only).
- **Decision**: discovery mode logs the large colour targets each frame, with size, layers,
  format and samples, and the profile names the one to use. A RenderDoc capture is optional and
  needs the owner's go-ahead because it launches the game.

### D10. Gaze source is an interface; only fixed and synthetic are built

- Evidence on delivery to a Linux host (all from this session's research):
  - Valve staff said eye tracking is used internally for foveated streaming and exposed to
    third parties over OSC, with OpenXR output on the roadmap (undated forum post).
  - The Steamworks input doc names the OpenXR eye-gaze extension and OpenVR eye-tracking
    actions without saying whether they apply to streamed apps.
  - SteamVR 2.18.2 sends eye openness over OSC when streaming from a Frame.
  - Community tools get gaze to PC VRChat over OSC; all assume a Windows PC.
- **Decision**: define the sample format and a source interface now (`contracts/`), implement
  fixed-centre and a synthetic source, and add a real source when hardware arrives.

## Repo conventions that apply (verified)

- Fork carried as a flake input, fixes as fork commits then `nix flake update`
  (`flake.nix:12-15`; `docs/steam-remote-play-streaming.md:76-86`).
- Packages register in `pkgs/default.nix` and are built in PR checks only when also exposed in
  `flake-modules/packages.nix`. `pkgs/steam-display-filter` is the closest injector precedent.
- No package has `passthru.tests`; Rust tests run in the build (`doCheck`); script tests are
  bats checks in `flake-modules/*-tests.nix`. No prek hook covers C, C++ or shell.
- Steam launch options are documented, not managed by Nix (`docs/` and ADR 0007).
- Layer precedent: lsfg-vk (`overlays/default.nix:701-758`) and MangoHud layer ordering
  (ADR 0011).
- Latest ADR is 0026; new ADRs add a row to `docs/adr/README.md`.

## Hardware facts used (measured, RX 9070 XT, RADV, Mesa 26.2.3)

Reproduced from `research/vrs-probe/results.txt`: rates applied exactly in 8x8 tiles for 1x1,
2x1, 1x2 and 2x2; 4x4 not available; no depth-buffer dependency; MSAA 1x, 2x, 4x honour the
rate and 8x falls back; multiview with a one-layer rate image gives identical rates in both
views; `{KEEP, REPLACE}` applies the attachment, `{KEEP, KEEP}` and `{KEEP, MIN}` do not; a
static pipeline rate works.
