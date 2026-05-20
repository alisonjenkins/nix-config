# EXPERIMENTAL: arm64 gaming via FEX-Emu + arm64 Steam/Proton.
#
# This module is best-effort. Valve's arm64 Steam preview landed late
# 2025; Proton arm64 builds are still maturing. FEX is the x86_64/i386
# binary translator that lets non-native Steam games run on Apple
# Silicon. Expect breakage — keep the host functional with this module
# disabled and only flip on when actively trying to game.
#
# Manual post-install steps (not nix-managed):
#   1. Download a FEX RootFS (Ubuntu 24.04 squashfs is the canonical
#      reference) from https://rootfs.fex-emu.com and extract to
#      /var/lib/fex-emu/RootFS/.
#   2. Initialize per-user FEX config:
#        FEXConfig    (or edit ~/.fex-emu/Config.json)
#   3. First Steam launch will fetch arm64 Steam runtime + Proton.
#
# Risks:
#   - pkgs.fex-emu availability on aarch64-linux varies; if missing,
#     bump nixpkgs_unstable or supply an overlay.
#   - Steam on arm64 is a separate package path from x86; verify
#     pkgs.steam evaluates on aarch64 before enabling.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-gaming-arm64;
in
{
  options.modules.desktop-gaming-arm64 = {
    enable = lib.mkEnableOption "experimental arm64 gaming via FEX + arm64 Steam/Proton";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = "modules.desktop-gaming-arm64 only makes sense on aarch64-linux (it wraps x86 translation via FEX). Disable on this host.";
      }
    ];

    # FEX provides binfmt_misc handlers for x86_64 and i386 ELF binaries.
    # The systemd unit upstream ships in fex-emu registers both formats
    # automatically when fex-emu is installed system-wide.
    boot.binfmt.emulatedSystems = [ "x86_64-linux" "i686-linux" ];

    environment.systemPackages = with pkgs; [
      fex          # x86_64/i386 -> aarch64 binary translator
      fex-headless # CLI-only variant, useful for testing without a Wayland session
      mangohud
      gamemode
      gamescope
    ];

    # programs.steam pulls in hardware.graphics.enable32Bit which is
    # x86-only — can't be enabled at the NixOS level on aarch64. The
    # path forward is one of:
    #   1. Flatpak Steam (com.valvesoftware.Steam) — brings its own
    #      i386 runtime, FEX translates via binfmt.
    #   2. Arm64 Steam preview from Valve (late 2025) — install as a
    #      manual fetchurl + makeWrapper once it stabilizes.
    # Neither needs programs.steam.enable.

    programs.gamemode.enable = true;

    # NOTE: hardware.graphics.enable32Bit is x86-only in NixOS. The
    # 32-bit graphics stack for FEX-translated games comes from the
    # FEX RootFS (Ubuntu squashfs at /var/lib/fex-emu/RootFS/), not
    # NixOS multilib.

    nixpkgs.config.allowUnfree = true;
  };
}
