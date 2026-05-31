# 04 — Sinden lightgun (+ border) — EXPERIMENTAL

**Verdict: PARTLY viable, exploratory on this exact platform.** No documented
SteamOS/Jovian-native Sinden success (best prior art = Batocera-on-Deck, a different OS).
**Defer to a separate `modules.emulation.sinden` gated `enable = false`.** Do the cheap,
safe declarative groundwork (driver package, udev, border assets); treat the end-to-end gun
experience as a **hardware-in-hand spike**, scoped single-gun, MAME + RetroArch first,
Plasma-desktop-preferred.

## Viability matrix

| Capability | Gaming Mode (gamescope) | Plasma 6 desktop |
|---|---|---|
| Mono driver runs, camera + serial access | HIGH (deps in nixpkgs) | HIGH |
| Pointer injection reaches the focused game | **MEDIUM–LOW [LOW-CONF]** | MEDIUM |
| Border at screen edge | MEDIUM (gamescope native ReShade `Border.fx`) | HIGH (RetroArch/MAME bezels); MEDIUM (layer-shell) |
| Single-gun arcade/console | MEDIUM | MEDIUM–HIGH |
| Dual-gun (P1+P2) | **non-functional / X11-only** | **non-functional on native Wayland** |
| Native Steam lightgun games | out of scope | out of scope |

## The sleeper blocker — pointer injection on Wayland

The driver moves the pointer via **SDL → X11 `XWarpPointer`**, which **cannot move the
pointer in a native Wayland session** (this is *why* Sinden ships a separate "Steam Deck
prototype" driver). The earlier "creates a `/dev/uinput` virtual mouse" claim was
**refuted** — nothing relies on uinput. **Implication:** a plan feeding a system-wide uinput
mouse into gamescope/Plasma-Wayland is likely wrong; lightgun input probably needs an
**XWayland** surface owning the pointer.

Compounding: **RetroArch native Wayland cannot enumerate multiple mice or do lightgun
absolute pointing at all** (libretro #16886, open). The only working RetroArch path is
**XWayland** (`WAYLAND_DISPLAY="" retroarch`). Whether that survives nesting **inside
gamescope** is unverified → Plasma desktop is the saner home for RetroArch lightgun.

**[ACTION, hardware-in-hand]:** `strace` the running `LightgunMono.exe` for
`openat("/dev/uinput")` vs an X11 socket / `XWarpPointer` to settle the injection path.

## Driver / software + NixOS packaging

- **Project:** `github.com/SindenLightgun/SindenLightgunLinux` (official; ships prebuilt
  `arch/x86_64/LightgunMono.exe` + `AForge*.dll` + native ELF helpers
  `libCameraInterface.so` / `libSdlInterface.so`; license = freely redistributable). Use
  `github.com/mdeguzis/sinden-lightgun-linux` **only** for setup/udev/overlay scripts +
  border assets (it does **not** contain the `arch/` binaries).
- **nixpkgs status:** nothing Sinden-related exists → package by hand.
- **Runtime deps (all in nixpkgs):** `mono` 6.14.1, `SDL` (SDL_compat 1.2.x → `libSDL-1.2.so.0`),
  `SDL_image`, `v4l-utils`/`libv4l`. (Drop `libjpeg` unless autoPatchelf reports it NEEDED.)
- **Packaging approach:** the input/camera path goes through the **native ELF helpers**
  (`libCameraInterface.so`/`libSdlInterface.so`), which link SDL 1.2 / V4L via standard ELF
  NEEDED → use **`autoPatchelfHook`** on those `.so` (buildInputs `SDL SDL_image v4l-utils
  glibc`) + a `makeWrapper`'d `mono $out/opt/sinden/LightgunMono.exe "$@"`. `buildFHSEnv` is
  the fallback. No AppImage is shipped (so `appimageTools` N/A); flatpak unused. Binaries are
  redistributable → `fetchFromGitHub` into the store is fine; **driver-written
  config/calibration must live on the persisted `/home`** (impermanence).
- **udev rule (clean-room; validate against live `udevadm info` first):** USB
  **`32e4:9210`** (may vary per unit). Composite device: UVC camera (V4L2) + HID + CDC-ACM
  serial (recoil/config).
  ```
  SUBSYSTEM=="usb",         ATTRS{idVendor}=="32e4", ATTRS{idProduct}=="9210", TAG+="uaccess"
  SUBSYSTEM=="tty",  SUBSYSTEMS=="usb", ATTRS{idVendor}=="32e4", ATTRS{idProduct}=="9210", GROUP="dialout", TAG+="uaccess"
  SUBSYSTEM=="video4linux", ATTRS{idVendor}=="32e4", ATTRS{idProduct}=="9210", TAG+="uaccess"
  ```
  + `users.users.<u>.extraGroups = [ "dialout" "video" ]` (upstream's `serial/uucp/uucm`
  are Arch/Debian-isms; `uaccess` on the logind seat is more reliable under greetd/gamescope).
- **Launch:** a user systemd unit running `mono LightgunMono.exe` (mouse mode default; must
  stay running during play).

## The border (no built-in overlay on Linux)

The border must come from the emulator, a post-process shader, or a compositor overlay —
**no single "OS draws it everywhere" solution.**

- **RetroArch (both modes) — HIGH, primary.** On-Screen Overlay renders the border *inside
  RetroArch's frame* → survives into gamescope. Ship Sinden overlay `.cfg`/`.png` presets
  (mdeguzis repo: `SindenBorderWhiteThin/Medium/Large/SuperThin`) into `overlays/borders/`;
  Overlay Opacity 1.0, "Hide Overlay in Menu" OFF.
- **MAME (both modes) — HIGH.** White-border `.lay` artwork + `whiteborder*.png` per ROM in
  MAME's artwork path; enable bezels. Per-ROM artwork required (Sinden Bezel Packs exist).
- **Gaming-mode fallback (non-RetroArch) — MEDIUM. Decky NOT required.** gamescope has
  native ReShade FX since SteamOS 3.5: `--reshade-effect <path> --reshade-technique-idx <i>`
  reading `~/.local/share/gamescope/reshade/Shaders/`. Ship a **pre-tuned `Border.fx`**
  (uniforms baked in — runtime uniforms can't be set) into a Nix-managed path + add the flag
  to the per-game gamescope invocation. Fully declarable. Caveats: adds latency (matters for
  a twitch gun); physical-edge alignment after gamescope scaling needs on-device Sinden
  calibration **[LOW-CONF]**.
- **Plasma overlay window — MEDIUM, fallback only.** `spillner/kde-screen-borders` via
  QtLayerShell; dep **is** in nixpkgs (`kdePackages.layer-shell-qt` 6.6.4) — only the
  `.qml` wrapper is unpackaged (small `fetchFromGitHub`, invoke via `qml`). Forces
  composition (kills VRR, adds latency) and is defeated by direct-scanout/exclusive
  fullscreen → only helps windowed emulators (PCSX2 windowed, Supermodel). **Does not work
  under gamescope** (no wlr-layer-shell to nested clients).
- **Avoid:** the Mesa-patched `spillner/vulkan-screen-border` (needs `mesa.overrideAttrs`,
  brittle, double-hooks gamescope's WSI layer). `vkbasalt` `Border.fx` is a community
  workaround (not Sinden-documented), reportedly broken on gamescope's Wayland backend
  (#1582) — Plasma/3D-standalone only, if ever.

## Per-emulator lightgun config & realistic support

Sinden = a USB-camera gun whose driver injects a **mouse**. All config is "mouse-as-lightgun"
+ a per-system border.

- **MAME (standalone) — most declarative.** `mame.ini`: `lightgun 1`, `mouse 1`,
  `multimouse 1`, `lightgun_device mouse`, `adstick_device mouse`, `offscreen_reload 0`
  (per-game `1` for e.g. area51), `ctrlr gunmouse`. Per-game `.ini` overrides effectively
  required. Dual-gun needs `<mapdevice>` by VID/PID + `lightgunprovider x11` + an Xorg
  "Floating" InputClass — **X11/Xorg only, no Wayland path.**
- **RetroArch — per-core device types** (NES fceumm Zapper, SMS Genesis Plus GX Phaser,
  PSX Beetle GunCon, Saturn Beetle Virtua Gun, Dreamcast Flycast Lightgun, Arcade MAME core,
  SNES snes9x Super Scope). Declarable — **but gated on the native-Wayland multi-mouse
  blocker (#16886): requires XWayland.**
- **Flycast — SINGLE gun only on Linux.** Device A/B = "Light Gun" works (near-declarative in
  `emu.cfg`). "Use Raw Input"/multi-mouse/dual-gun is **Windows-only** (`#ifdef _WIN32`);
  writing `RawInput` via `home.file` is a no-op on Linux. For 2-player Dreamcast/NAOMI use the
  RetroArch flycast core (verify multi-mouse).
- **PCSX2 — GunCon2 single-gun** (native in PCSX2-Qt; bind X/Y to a Pointer/mouse). Dual-mouse
  incomplete (#12252). Declarable in `PCSX2.ini`.
- **Dolphin (Wii) — OUT OF SCOPE** (IR pointer, not optical-border lightgun).

**Realistically supported (single gun):** standalone MAME, PCSX2 (GunCon2), Flycast (single),
RetroArch (NES/SMS/PSX/Saturn/SNES) **under XWayland — best in Plasma desktop.**
Gaming-mode/gamescope lightgun is fragile → flag experimental.

**Dual-gun:** Sinden v2.07+ runs two guns in one instance but P2 = "Not Implemented" (manual
`SindenLightgun-P2Start`); mouse indices reshuffle on replug. On this platform dual-gun is
**non-functional on native Wayland** and forces X11/XWayland per emulator. Ship single-gun as
the supported tier; dual-gun = advanced/manual/X11.

**Recoil:** trigger-driven, handled inside the Mono driver (USB solenoid, toggled in
`LightgunMono.exe.config`) → "just works" with the driver running; no per-emulator config in
the default path. Hit-driven recoil forks are Windows-oriented, Linux-unverified.

## Option schema (sketch)

```nix
options.modules.emulation.sinden = {
  enable = lib.mkEnableOption "Sinden Lightgun driver + udev + border assets (EXPERIMENTAL)";
  usbIds = lib.mkOption {
    type = lib.types.submodule { options = {
      vendorId  = lib.mkOption { type = lib.types.str; default = "32e4"; };
      productId = lib.mkOption { type = lib.types.str; default = "9210"; };   # verify per unit
    }; };
    default = {};
  };
  driver = {
    package   = lib.mkOption { type = lib.types.package; };                   # hand-rolled (autoPatchelf + mono)
    mode      = lib.mkOption { type = lib.types.enum [ "mouse" "joystick" ]; default = "mouse"; };
    autostart = lib.mkEnableOption "user systemd unit running LightgunMono.exe";
  };
  border = {
    retroarchOverlays = lib.mkEnableOption "ship RetroArch Sinden border presets (primary)";
    mameArtwork       = lib.mkOption { type = lib.types.attrsOf lib.types.path; default = {}; };  # rom -> .lay/.png dir
    gamescopeReshade  = {
      enable   = lib.mkEnableOption "pre-tuned Border.fx + gamescope --reshade-effect (gaming-mode fallback)";
      borderFx = lib.mkOption { type = lib.types.path; };
    };
    plasmaLayerShell  = lib.mkEnableOption "layer-shell overlay (Plasma, non-exclusive only) [LOW-CONF]";
  };
  guns = lib.mkOption { type = lib.types.ints.between 1 2; default = 1; };     # dual is X11-only
};
```

**Unavoidably manual:** first-time aim **calibration** (per-display/per-emulator, interactive;
no unified Linux UI), per-AppID Steam Input apply, gamescope `--reshade-effect` flag if
launched via Steam launch options, and verifying the injection/XWayland path.
