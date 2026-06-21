# Self-maintaining Nix store for nix-darwin hosts.
#
# Mirrors the NixOS maintenance set in modules/base, but using nix-darwin's
# option shapes (GC/optimise schedules are launchd `interval` attrsets, not
# systemd `dates` strings). Kept as a separate darwin module rather than
# branching modules/base on isDarwin, per the repo's cross-platform split.
#
# All values are mkDefault so a host can override per-disk (e.g. a larger
# min-free on a machine that does big builds).
{ lib, ... }:
{
  nix.gc = {
    automatic = lib.mkDefault true;
    interval = lib.mkDefault {
      Weekday = 0;
      Hour = 3;
      Minute = 15;
    };
    options = lib.mkDefault "--delete-older-than 60d";
  };

  # Scheduled hardlink dedup sweep, complementing per-build
  # auto-optimise-store below.
  nix.optimise = {
    automatic = lib.mkDefault true;
    interval = lib.mkDefault {
      Weekday = 0;
      Hour = 4;
      Minute = 15;
    };
  };

  nix.settings = {
    auto-optimise-store = lib.mkDefault true;
    # Free-space-triggered GC: the daemon GCs mid-build when free space drops
    # below min-free, freeing until max-free is available — the safety net
    # that stops the store filling the disk between scheduled GC runs.
    min-free = lib.mkDefault (5 * 1024 * 1024 * 1024); # 5 GiB
    max-free = lib.mkDefault (20 * 1024 * 1024 * 1024); # 20 GiB
  };
}
