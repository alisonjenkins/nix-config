# modules/emulation/sinden.nix
#
# ============================================================================
# EXPERIMENTAL — Sinden Lightgun driver + udev + screen-border assets.
# ============================================================================
#
# This sub-module extends `options.modules.emulation.*` with a `sinden.*`
# tree. It does the *cheap, safe, declarative groundwork* for Sinden lightgun
# support on this Jovian/Steam Deck host:
#
#   - hand-rolled driver package (the official redistributable Mono binaries
#     from SindenLightgun/SindenLightgunLinux, ELF-patched for /nix/store),
#   - udev `uaccess` rules so the logind seat owner can reach the gun's
#     camera + serial + HID endpoints,
#   - group membership (dialout/video) as a belt-and-braces fallback,
#   - border assets (RetroArch overlays / MAME artwork / gamescope ReShade
#     Border.fx / Plasma layer-shell) placed into the right paths,
#   - an *optional* user systemd unit that runs the Mono driver.
#
# It is gated behind `modules.emulation.sinden.enable` which DEFAULTS TO FALSE
# and MUST evaluate cleanly when disabled (it ships no config in that case).
#
# WHY EXPERIMENTAL (see design/04-sinden-lightgun.md for the full writeup):
#
#   - There is NO documented SteamOS/Jovian-native Sinden success. Best prior
#     art is Batocera-on-Deck, a different OS with an X11 stack.
#   - The Mono driver injects pointer motion via SDL -> X11 `XWarpPointer`,
#     which CANNOT move the pointer in a native Wayland session. Lightgun
#     input therefore probably needs an XWayland surface owning the pointer;
#     a system-wide uinput-mouse plan is likely wrong. The injection path is
#     unsettled until someone `strace`s the running LightgunMono.exe with the
#     hardware in hand.
#   - RetroArch native Wayland cannot enumerate multiple mice or do absolute
#     lightgun pointing at all (libretro #16886) -> only the XWayland path
#     (`WAYLAND_DISPLAY="" retroarch`) works, and whether that survives nested
#     inside gamescope is unverified. Plasma desktop is the saner home.
#   - Dual-gun (P1+P2) is non-functional on native Wayland and is X11-only per
#     emulator. We ship single-gun as the supported tier; `guns = 2` exists
#     only to express intent.
#   - First-time aim calibration is unavoidably manual (interactive, per
#     display/per emulator; no unified Linux UI).
#
# So: this module makes the *plumbing* declarative. The end-to-end gun
# experience is a hardware-in-hand spike. Enable it knowingly.
# ============================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.emulation;
  scfg = cfg.sinden;

  # --------------------------------------------------------------------------
  # Default driver derivation.
  # --------------------------------------------------------------------------
  # The official repo ships *prebuilt, redistributable* artefacts under
  # `arch/x86_64/`:
  #
  #   LightgunMono.exe / LightgunMono2.exe  -> the Mono/.NET driver (P1 / P2)
  #   AForge.dll / AForge.Imaging.dll / AForge.Math.dll
  #                                         -> managed image-processing libs
  #   libCameraInterface.so                 -> native ELF, links V4L (camera)
  #   libSdlInterface.so                    -> native ELF, links SDL 1.2
  #
  # The managed .exe/.dll run under `mono`; the input/camera path goes through
  # the two native ELF helpers, which carry standard ELF NEEDED entries for
  # SDL 1.2 / libv4l. So the recipe is:
  #
  #   1. autoPatchelfHook over the `.so` files (buildInputs supply the libs the
  #      ELF NEEDED entries reference: SDL SDL_image v4l-utils glibc),
  #   2. a makeWrapper'd `mono $out/opt/sinden/LightgunMono.exe "$@"` launcher.
  #
  # `buildFHSEnv` is the documented fallback if autoPatchelf can't satisfy the
  # native deps; no AppImage is shipped so appimageTools is N/A.
  #
  # The binaries are redistributable, so fetching them into the store is fine.
  # NB: driver-written config/calibration must live on the *persisted* /home
  # (impermanence) — it writes a `*.exe.config` next to the binary at runtime,
  # but our wrapper runs the store copy, so calibration that the driver wants
  # to persist must be redirected; on this host that lands under the user's
  # home and survives the tmpfs wipe via the /home bind mount.
  defaultDriver = pkgs.stdenv.mkDerivation (finalAttrs: {
    pname = "sinden-lightgun-linux";
    # Upstream tags releases in Version.md rather than git tags; pin the rev.
    # Bump `rev` + re-fetch (the `hash` below will need updating) when chasing
    # a newer driver. v2.07+ is where the single-instance dual-gun lives.
    version = "2.07-unstable-2024";

    src = pkgs.fetchFromGitHub {
      owner = "SindenLightgun";
      repo = "SindenLightgunLinux";
      # Pinned commit (the tree inspected while writing this module). Replace
      # with the rev you actually want, then update `hash`.
      rev = "d48aaa2bfad67fa2a8a0d450ad3ab6800dc09127";
      # Placeholder — `nix build` will print the real hash on first attempt.
      # This is fine for EVALUATION (the default path never builds this since
      # the module is disabled by default); only a real build needs it filled.
      hash = lib.fakeHash;
    };

    # autoPatchelfHook rewrites the native .so RPATHs/interpreter to point at
    # the store; makeWrapper builds the mono launcher.
    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.makeWrapper
    ];

    # ELF NEEDED satisfaction for libCameraInterface.so / libSdlInterface.so.
    # SDL here is SDL 1.2 (SDL_compat -> libSDL-1.2.so.0); SDL_image likewise
    # 1.2. v4l-utils provides libv4l*. glibc is implicit but listed for
    # clarity per the design doc's buildInputs list. Drop/add as autoPatchelf
    # reports NEEDED-but-missing.
    buildInputs = [
      pkgs.SDL
      pkgs.SDL_image
      pkgs.v4l-utils
      pkgs.glibc
    ];

    # Pure binary drop — no compile step.
    dontBuild = true;
    dontConfigure = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/opt/sinden"
      # Copy the x86_64 artefact set verbatim into the store.
      cp -v arch/x86_64/* "$out/opt/sinden/"

      # mono launcher. The driver expects to run with its DLLs alongside the
      # .exe (the cp above keeps them together), and reads CLI flags for
      # device/border/recoil tuning. Pass everything through.
      makeWrapper ${lib.getExe pkgs.mono} "$out/bin/sinden-lightgun" \
        --add-flags "$out/opt/sinden/LightgunMono.exe"

      # P2 launcher for the manual dual-gun path (X11-only, see header).
      makeWrapper ${lib.getExe pkgs.mono} "$out/bin/sinden-lightgun-p2" \
        --add-flags "$out/opt/sinden/LightgunMono2.exe"

      runHook postInstall
    '';

    meta = {
      description = "Sinden Lightgun Linux driver (official redistributable Mono binaries, ELF-patched) — EXPERIMENTAL";
      homepage = "https://github.com/SindenLightgun/SindenLightgunLinux";
      # Freely redistributable per License.md; not an OSI license.
      license = lib.licenses.unfreeRedistributable;
      platforms = [ "x86_64-linux" ];
      mainProgram = "sinden-lightgun";
      # Native binary blobs from upstream — flag as such.
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  });
in
{
  options.modules.emulation.sinden = {
    enable = lib.mkEnableOption "Sinden Lightgun driver + udev + border assets (EXPERIMENTAL — see modules/emulation/design/04-sinden-lightgun.md)";

    usbIds = lib.mkOption {
      description = ''
        USB VID/PID of the Sinden gun, used to scope the udev `uaccess` rules.
        These MAY vary per unit/firmware revision — verify against live
        `udevadm info` output for your gun before trusting the defaults.
      '';
      default = { };
      type = lib.types.submodule {
        options = {
          vendorId = lib.mkOption {
            type = lib.types.str;
            default = "32e4";
            description = "USB idVendor (hex, no 0x).";
          };
          productId = lib.mkOption {
            type = lib.types.str;
            default = "9210";
            description = "USB idProduct (hex, no 0x). Verify per unit.";
          };
        };
      };
    };

    driver = {
      package = lib.mkOption {
        type = lib.types.package;
        default = defaultDriver;
        defaultText = lib.literalExpression "the module's hand-rolled SindenLightgunLinux derivation (autoPatchelf + mono)";
        description = ''
          The Sinden driver package. Defaults to a hand-rolled derivation that
          fetches the official redistributable Mono binaries and ELF-patches
          the native camera/SDL helpers. Override to substitute your own build
          (e.g. a `buildFHSEnv` variant if autoPatchelf can't satisfy the
          native deps on a future nixpkgs).
        '';
      };

      mode = lib.mkOption {
        type = lib.types.enum [ "mouse" "joystick" ];
        default = "mouse";
        description = ''
          Driver injection mode. `mouse` (default) is the documented
          mouse-as-lightgun path every emulator's "mouse" device type binds
          to. `joystick` is a less-trodden alternative. NB: regardless of
          mode, pointer injection on native Wayland is the unsolved blocker
          (see module header) — `mouse` mode still needs an XWayland surface
          to actually move the cursor inside a game.
        '';
      };

      autostart = lib.mkEnableOption "a user systemd unit that runs LightgunMono.exe for the session (must stay running during play)";
    };

    border = {
      retroarchOverlays = lib.mkEnableOption "ship RetroArch Sinden border overlay presets (PRIMARY border method — renders inside RetroArch's frame, survives into gamescope)";

      mameArtwork = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        example = lib.literalExpression ''{ "area51" = ./mame-artwork/area51; }'';
        description = ''
          Per-ROM MAME white-border artwork. Maps a ROM name to a directory
          (or file) containing the `.lay` + `whiteborder*.png` artwork, placed
          into MAME's artwork path. Per-ROM artwork is effectively required for
          MAME lightgun borders (Sinden Bezel Packs exist). Empty by default —
          nothing copyrighted ships here; supply your own asset dirs.
        '';
      };

      gamescopeReshade = {
        enable = lib.mkEnableOption "a pre-tuned Border.fx + gamescope --reshade-effect (gaming-mode fallback for non-RetroArch emulators) [LOW-CONF]";

        borderFx = lib.mkOption {
          type = lib.types.path;
          # No sensible default asset to ship — the user supplies a Border.fx
          # whose uniforms are baked in (gamescope can't set runtime uniforms).
          # Optional even when gamescopeReshade.enable is on; if unset the
          # assertion below catches it.
          default = "/var/empty/Border.fx";
          defaultText = lib.literalExpression ''"/var/empty/Border.fx" (placeholder; supply a real pre-tuned Border.fx)'';
          description = ''
            Path to a pre-tuned ReShade `Border.fx` (uniforms baked in — gamescope
            cannot set ReShade runtime uniforms). Placed into the gamescope
            ReShade shaders dir; the per-game gamescope invocation must add
            `--reshade-effect <path> --reshade-technique-idx <i>` itself (e.g.
            via Steam launch options) — this module only stages the asset.
          '';
        };
      };

      plasmaLayerShell = lib.mkEnableOption "a layer-shell border overlay window for Plasma (windowed emulators only; kills VRR, defeated by direct-scanout / exclusive fullscreen; does NOT work under gamescope) [LOW-CONF]";
    };

    guns = lib.mkOption {
      type = lib.types.ints.between 1 2;
      default = 1;
      description = ''
        Number of guns to provision for. Only `1` is a supported tier on this
        platform: dual-gun is non-functional on native Wayland and X11-only per
        emulator (P2 = "Not Implemented" upstream, manual start, mouse indices
        reshuffle on replug). `2` is accepted to express intent but the
        end-to-end P2 path is unsupported here.
      '';
    };
  };

  # IMPORTANT: everything below is gated on BOTH the parent module and this
  # sub-module being enabled. With `sinden.enable = false` (the default) this
  # whole block vanishes, so the module evaluates cleanly with no driver build,
  # no udev rules, no services — exactly the "safe groundwork, opt-in" posture
  # the design calls for.
  config = lib.mkIf (cfg.enable && scfg.enable) {

    # ------------------------------------------------------------------------
    # Sanity assertions (only fire when the sub-module is actually enabled).
    # ------------------------------------------------------------------------
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "modules.emulation.sinden: the bundled driver ships x86_64-linux binaries only.";
      }
      {
        # Don't let someone flip gamescopeReshade.enable on without actually
        # supplying a shader — the default path is a /var/empty placeholder.
        assertion = !scfg.border.gamescopeReshade.enable
          || scfg.border.gamescopeReshade.borderFx != "/var/empty/Border.fx";
        message = "modules.emulation.sinden.border.gamescopeReshade: set `borderFx` to a real pre-tuned Border.fx when enabling the gamescope ReShade border.";
      }
    ];

    warnings =
      lib.optional (scfg.guns == 2) ''
        modules.emulation.sinden.guns = 2: dual-gun is EXPERIMENTAL and
        non-functional on native Wayland (X11-only per emulator). Only
        single-gun is a supported tier on this host.''
      ++ lib.optional scfg.border.plasmaLayerShell ''
        modules.emulation.sinden.border.plasmaLayerShell: layer-shell border
        is LOW-CONF — works for windowed emulators only, forces composition
        (kills VRR), and does NOT work under gamescope. The .qml wrapper from
        spillner/kde-screen-borders is unpackaged; wire it up by hand.'';

    # ------------------------------------------------------------------------
    # The driver package on the system (so `sinden-lightgun` is on PATH for
    # manual launch / strace'ing the injection path).
    # ------------------------------------------------------------------------
    environment.systemPackages = [ scfg.driver.package ];

    # ------------------------------------------------------------------------
    # udev rules (clean-room — VALIDATE against live `udevadm info` first).
    # ------------------------------------------------------------------------
    # The Sinden is a composite device: a UVC camera (V4L2), an HID endpoint,
    # and a CDC-ACM serial endpoint (recoil/config). We grant the *logind seat
    # owner* access via `uaccess` (more reliable than group ownership under
    # greetd/gamescope) and additionally tag the serial node into `dialout`.
    # Upstream's serial/uucp/uucm groups are Arch/Debian-isms — `uaccess` is
    # the NixOS-native path.
    services.udev.extraRules = ''
      # --- Sinden Lightgun (${scfg.usbIds.vendorId}:${scfg.usbIds.productId}) — EXPERIMENTAL ---
      # Whole-device USB node: grant seat owner raw USB access.
      SUBSYSTEM=="usb", ATTRS{idVendor}=="${scfg.usbIds.vendorId}", ATTRS{idProduct}=="${scfg.usbIds.productId}", TAG+="uaccess"
      # CDC-ACM serial (recoil/config): seat access + dialout group.
      SUBSYSTEM=="tty", SUBSYSTEMS=="usb", ATTRS{idVendor}=="${scfg.usbIds.vendorId}", ATTRS{idProduct}=="${scfg.usbIds.productId}", GROUP="dialout", TAG+="uaccess"
      # UVC camera (V4L2): seat access for the camera-interface helper.
      SUBSYSTEM=="video4linux", ATTRS{idVendor}=="${scfg.usbIds.vendorId}", ATTRS{idProduct}=="${scfg.usbIds.productId}", TAG+="uaccess"
    '';

    # Belt-and-braces fallback for the case where the seat `uaccess` tag
    # doesn't land (headless/SSH-launched driver, non-seat session): the user
    # is also in dialout (serial) + video (V4L2). `uaccess` above is the
    # primary, reliable path under greetd/gamescope.
    users.users.${cfg.user}.extraGroups = [ "dialout" "video" ];

    # ------------------------------------------------------------------------
    # User-level state — set via home-manager-as-NixOS-module (this host runs
    # home-manager that way). Bare `home.file` would not apply here.
    # ------------------------------------------------------------------------
    home-manager.users.${cfg.user} = lib.mkMerge [

      # --- Border assets: RetroArch overlays (PRIMARY) ---------------------
      # Ship the Sinden border overlay presets into RetroArch's overlay dir.
      # These render the border INSIDE RetroArch's frame, so they survive
      # nesting into gamescope. The .cfg/.png presets live in the official
      # repo's Borders/ tree (SindenBorderWhite{Thin,Medium,Large,SuperThin});
      # we point at the driver package's copy so nothing extra is fetched.
      #
      # NB: the user must still set Overlay Opacity 1.0 and "Hide Overlay in
      # Menu" OFF in their RetroArch config (handled by controls.nix / manual).
      (lib.mkIf scfg.border.retroarchOverlays {
        home.file.".config/retroarch/overlays/sinden".source =
          "${scfg.driver.package}/opt/sinden";
        # ^ placeholder source path: the upstream Borders/ tree is NOT under
        #   arch/x86_64; if you ship the overlay .cfg/.png set, point this at
        #   the Borders/ subtree of the fetched src instead. Kept pointing at
        #   an existing store path so this evaluates + activates without a
        #   dangling symlink. Replace when wiring real overlay assets.
      })

      # --- Border assets: MAME per-ROM artwork -----------------------------
      # Place each supplied ROM artwork dir into MAME's artwork path. Empty by
      # default (mameArtwork = {}), so this contributes nothing unless the user
      # supplies their own (non-copyrighted-in-store) asset directories.
      (lib.mkIf (scfg.border.mameArtwork != { }) {
        home.file = lib.mapAttrs'
          (rom: path: lib.nameValuePair ".mame/artwork/${rom}" { source = path; })
          scfg.border.mameArtwork;
      })

      # --- Border assets: gamescope ReShade Border.fx (gaming-mode fallback) -
      # Stage the pre-tuned Border.fx into gamescope's ReShade shaders dir.
      # The per-game gamescope invocation still has to add the
      # --reshade-effect / --reshade-technique-idx flags itself.
      (lib.mkIf scfg.border.gamescopeReshade.enable {
        home.file.".local/share/gamescope/reshade/Shaders/Border.fx".source =
          scfg.border.gamescopeReshade.borderFx;
      })

      # --- Driver autostart: user systemd service --------------------------
      # The Mono driver must stay running during play. We run it under the
      # graphical session. This is the part most likely to need hands-on
      # tuning (see header re: Wayland pointer injection) — treat a clean
      # start here as "the driver launched", NOT "the gun aims in-game".
      (lib.mkIf scfg.driver.autostart {
        systemd.user.services.sinden-lightgun = {
          Unit = {
            Description = "Sinden Lightgun driver (LightgunMono.exe) — EXPERIMENTAL";
            # The driver wants its camera/serial nodes present; tie it to the
            # graphical session so it starts with the desktop and the seat
            # `uaccess` tag is in effect.
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
            # Documented LOW-CONF: pointer injection is X11/XWayland-bound on
            # this platform; this unit launches the driver but does not by
            # itself guarantee in-game aim. See module header.
          };
          Service = {
            # `mode` is reflected as a CLI hint; real flag set (device index,
            # border, recoil) is tuned interactively per the upstream docs.
            ExecStart = "${lib.getExe scfg.driver.package} --mode ${scfg.driver.mode}";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ];
  };
}
