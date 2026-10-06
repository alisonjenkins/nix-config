# 0027. Add foveated rendering to D3D11 VR games by forking DXVK, behind an environment gate

- Status: Proposed
- Date: 2026-10-06

## Context

The heavy D3D11 VR games the owner has (Skyrim VR, Fallout 4 VR, BONEWORKS, Blade & Sorcery,
Elite Dangerous and others) have no foveated rendering, and most of their studios will not add it.
Spec 005 (`specs/005-vr-foveated-rendering-injector/`) wants it injected, measured and recorded per
game, on Linux with an AMD GPU. The Steam Frame's own foveated streaming only lowers bitrate; the
PC GPU still shades every pixel.

No injector was found for this setup. The Windows tools (OpenXR-Toolkit, VRPerfKit, PimaxMagic4All)
use Nvidia-only D3D11 extensions or need a game that already supports quad views. Under Proton,
D3D11 runs on DXVK, which has no variable-rate-shading code at all (read in DXVK master 3.1.1). The
one Linux precedent, a patched DXVK for VRChat, was tested only on an Nvidia GPU and uses a 16x16
tile and a two-layer rate image, neither of which this GPU accepts.

What the RX 9070 XT (RADV, Mesa 26.2.3) does, measured by `research/vrs-probe/` in the spec and
reproduced in `results.txt`: rates apply exactly in 8x8 tiles; the coarsest rate is 2x2; 8x MSAA
ignores the rate; a one-layer rate image serves both eyes of a multiview target and both layers of
a two-layer target with no view mask (DXVK's instanced-stereo case); a two-layer rate image is a
validation error and RADV ignores layer 1; `{KEEP, REPLACE}` with a 1x1 base rate is the minimum
correct setup. A two-layer rate image or per-eye masks are therefore not an option here.

What the owner's setup looks like (read locally): the default runner is `DW-Proton Latest`
(`dwproton-11.0-14`) with DXVK `v3.1.1-27-g25ca63f`. Runners are real downloaded directories under
`compatibilitytools.d`, not Nix store links.

## Decision

- **Patch DXVK, carried as a fork consumed as a flake input**, the way the niri fork is
  (`docs/steam-remote-play-streaming.md`, section on the niri input): fixes are fork commits with
  their tests first, then `nix flake update`. The base is upstream `v3.1.1`, the tag the owner's VR
  runner is built from.
- **Foveation is off unless a game opts in.** The patched DXVK enables the shading-rate extension
  and builds shading-rate pipelines only when the launch option sets `DXVK_FOVEATION`. With it
  unset the pipelines are identical to stock, and a measurement run checks that (SC-005).
- **Deliver it as a separate compat tool directory** (for example `DW-Proton Foveated`) made from
  the owner's DW-Proton release with only its DXVK replaced, chosen per game in Steam. It is not a
  layer over a Nix store Proton, because the owner's runners are not in the store, and it is not
  written into the runner directories the updater manages. The build route (a derivation fetching the
  pinned release, or an activation step copying the current runner) is settled by spike S3.
- **Profiles live in DXVK's own config file.** A user config supports `[Fallout4VR.exe]` sections
  and any key, read by `DXVK_CONFIG_FILE` (verified in DXVK 2.6.2 and 3.1.1), so a home-manager
  module generates one file and no new parser is written.
- **Measure before and after with GPU timestamp queries inside the fork and a power sampler on the
  discrete card**, and keep a go, no-go or inconclusive verdict per game. Any change beyond run-to-run
  noise counts; there is no minimum percentage.
- **Defer a Vulkan layer for Vulkan-native games and any gaze source** until the D3D11 path has a
  go verdict and a Steam Frame is in hand. The gaze source is an interface from the start.

## Alternatives rejected

- **A Vulkan implicit layer for everything.** DXVK builds pipelines from graphics pipeline libraries,
  so a layer would have to rewrite those create infos from outside to add the shading-rate state and
  the creation flag. The fork edits them where they are built. A layer stays the right shape for
  games that are Vulkan-native.
- **Windows tools under Wine.** They depend on Nvidia-only D3D11 extensions that DXVK does not
  expose.
- **Replacing DXVK files in the Proton install, or copying DLLs into each prefix.** A runner update
  wipes the first; the second can drift from the runner's own DXVK. Both remain fallbacks.
- **A separate JSON or TOML profile with a new parser in DXVK.** Extra parser code inside a
  third-party codebase for something its config file already does.
- **Making a 4x4 rate or per-eye masks work.** The GPU has neither.

## Consequences

- The feature is limited to GPU and driver combinations it has been verified on; elsewhere it disables
  itself and logs the reason (FR-017), because the one tested driver does not enforce a rule the
  validation layer treats as required: attachment pipelines should carry
  `VK_PIPELINE_CREATE_RENDERING_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR`.
- Both eyes share one rate mask on this GPU, so the fixed region is the same in both eyes and a
  future gaze source is reduced to one combined centre.
- The fork must be rebased as the runner's DXVK moves; the patch is kept to two new files and small
  hooks to make that cheap.
- Games with anti-cheat are unsupported. The feature cannot detect anti-cheat from inside a game, so
  that is a documentation warning.
- Unproven: that the eye-image pass can be told apart per game (spike S2 and the discovery mode);
  that foveation helps any of the owner's games (the measurement decides, and a no-go is a valid
  result); that Proton leaves `DXVK_CONFIG_FILE` alone and `/nix/store` is visible in the Steam
  container (the first game run); and whether the Steam Frame delivers gaze to a streamed app on a
  Linux host (nothing is reported for Linux hosts).
