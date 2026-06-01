# modules/emulation/catalogue.nix
#
# The console catalogue: which consoles exist, their valid emulator BACKENDS
# (verified nixpkgs attrs — RetroArch libretro cores + standalone packages, all
# confirmed present on this host's pkgs), the ROM directory name, and file
# extensions. This is pure data, imported by:
#   - default.nix  -> generates the consoles.* options + the package union
#   - content.nix  -> derives a B2 ROM sync set per enabled console
#   - (frontend)   -> RetroFE collections, one per enabled console
#
# A backend spec is ONE of:
#   { core = "<libretro attr>"; }  -> a RetroArch core (pulled via retroarch.withCores)
#   { pkg  = "<pkgs attr>"; }      -> a standalone emulator package
#
# `emulators` on a console is a LIST of backend keys (install multiple), defaulting
# to `default`. The console's single `enable` gates its emulators, its games
# (content sync) and its per-console theme together.
#
# NB: pkgs.citron is this repo's overlay emulator (not the upstream Rust crate);
# valid only with self.overlays.additions applied (the host does).
{
  nes = {
    romDir = "nes"; extensions = [ "nes" "unf" "fds" "zip" "7z" ];
    default = [ "retroarch-fceumm" ];
    backends = {
      "retroarch-fceumm" = { core = "fceumm"; };
      "retroarch-mesen" = { core = "mesen"; };
    };
  };
  snes = {
    romDir = "snes"; extensions = [ "sfc" "smc" "zip" "7z" ];
    default = [ "retroarch-snes9x" ];
    backends = {
      "retroarch-snes9x" = { core = "snes9x"; };
      "retroarch-bsnes" = { core = "bsnes"; };
      "retroarch-bsnes-hd" = { core = "bsnes-hd"; };
    };
  };
  n64 = {
    romDir = "n64"; extensions = [ "n64" "z64" "v64" "zip" ];
    default = [ "retroarch-mupen64plus" ];
    backends = {
      "retroarch-mupen64plus" = { core = "mupen64plus"; }; # = libretro-mupen64plus-next
      "retroarch-parallel-n64" = { core = "parallel-n64"; };
      "mupen64plus" = { pkg = "mupen64plus"; };
      "ares" = { pkg = "ares"; };
    };
  };
  gb = {
    romDir = "gb"; extensions = [ "gb" "zip" ];
    default = [ "retroarch-gambatte" ];
    backends."retroarch-gambatte" = { core = "gambatte"; };
  };
  gbc = {
    romDir = "gbc"; extensions = [ "gbc" "zip" ];
    default = [ "retroarch-gambatte" ];
    backends."retroarch-gambatte" = { core = "gambatte"; };
  };
  gba = {
    romDir = "gba"; extensions = [ "gba" "zip" ];
    default = [ "mgba" ];
    backends = {
      "mgba" = { pkg = "mgba"; };
      "retroarch-mgba" = { core = "mgba"; };
    };
  };
  genesis = {
    romDir = "genesis"; extensions = [ "md" "gen" "bin" "smd" "zip" ];
    default = [ "retroarch-genesis-plus-gx" ];
    backends."retroarch-genesis-plus-gx" = { core = "genesis-plus-gx"; };
  };
  saturn = {
    romDir = "saturn"; extensions = [ "chd" "cue" "iso" ];
    default = [ "retroarch-beetle-saturn" ];
    backends."retroarch-beetle-saturn" = { core = "beetle-saturn"; }; # = libretro-mednafen-saturn
  };
  ps1 = {
    romDir = "psx"; extensions = [ "chd" "cue" "pbp" "m3u" ];
    default = [ "retroarch-swanstation" ];
    backends = {
      "retroarch-swanstation" = { core = "swanstation"; };
      "retroarch-beetle-psx-hw" = { core = "beetle-psx-hw"; }; # = libretro-mednafen-psx-hw
    };
  };
  ps2 = {
    romDir = "ps2"; extensions = [ "iso" "chd" "bin" "cso" ];
    default = [ "pcsx2" ];
    backends."pcsx2" = { pkg = "pcsx2"; };
  };
  ps3 = {
    romDir = "ps3"; extensions = [ ]; # PS3 titles are folders/pkgs, not single files
    default = [ "rpcs3" ];
    backends."rpcs3" = { pkg = "rpcs3"; };
  };
  psp = {
    romDir = "psp"; extensions = [ "iso" "cso" "chd" "pbp" ];
    default = [ "ppsspp" ];
    backends = {
      "ppsspp" = { pkg = "ppsspp"; };
      "retroarch-ppsspp" = { core = "ppsspp"; };
    };
  };
  gamecube = {
    romDir = "gc"; extensions = [ "iso" "rvz" "gcm" "ciso" ];
    default = [ "dolphin" ];
    backends = {
      "dolphin" = { pkg = "dolphin-emu"; };
      "retroarch-dolphin" = { core = "dolphin"; };
    };
  };
  wii = {
    romDir = "wii"; extensions = [ "iso" "rvz" "wbfs" "wad" ];
    default = [ "dolphin" ];
    backends."dolphin" = { pkg = "dolphin-emu"; };
  };
  wiiu = {
    romDir = "wiiu"; extensions = [ "wua" "rpx" "wud" "wux" ];
    default = [ "cemu" ];
    backends."cemu" = { pkg = "cemu"; };
  };
  ds = {
    romDir = "nds"; extensions = [ "nds" "zip" ];
    default = [ "melonds" ];
    backends = {
      "melonds" = { pkg = "melonds"; };
      "retroarch-melonds" = { core = "melonds"; };
      "desmume" = { pkg = "desmume"; };
    };
  };
  "3ds" = {
    romDir = "3ds"; extensions = [ "3ds" "cci" "cxi" "app" "cia" ];
    default = [ "azahar" ];
    backends."azahar" = { pkg = "azahar"; };
  };
  switch = {
    romDir = "switch"; extensions = [ "nsp" "xci" ];
    default = [ "citron" ];
    keys = true; # needs prod.keys/title.keys + firmware (own dumps; see content.nix)
    backends = {
      "citron" = { pkg = "citron"; }; # repo overlay emulator (NOT upstream pkgs.citron)
      "ryubing" = { pkg = "ryubing"; }; # nixpkgs; ships NO udev rule (bin: ryujinx)
      # eden: nixpkgs HAS a source-built eden that ships 72-yuzu-input.rules, BUT
      # this repo's overlay shadows it with an AppImage wrapper that may NOT ship
      # the rule — so services.udev.packages=[eden] in default.nix can be a no-op.
      # See audit follow-up: verify the rule ships, or source it explicitly.
      "eden" = { pkg = "eden"; };
    };
  };
  dreamcast = {
    romDir = "dreamcast"; extensions = [ "chd" "cdi" "gdi" "cue" ];
    default = [ "flycast" ];
    backends = {
      "flycast" = { pkg = "flycast"; };
      "retroarch-flycast" = { core = "flycast"; };
    };
  };
  arcade = {
    romDir = "arcade"; extensions = [ "zip" "7z" "chd" ];
    default = [ "mame" ];
    backends = {
      "mame" = { pkg = "mame"; };
      "retroarch-mame" = { core = "mame"; };
      "retroarch-mame2003-plus" = { core = "mame2003-plus"; };
    };
  };
  xbox = {
    romDir = "xbox"; extensions = [ "iso" "xiso" ];
    default = [ "xemu" ];
    backends."xemu" = { pkg = "xemu"; };
  };
  ps4 = {
    romDir = "ps4"; extensions = [ "pkg" "bin" ];
    default = [ "shadps4" ];
    backends."shadps4" = { pkg = "shadps4"; };
  };
}
