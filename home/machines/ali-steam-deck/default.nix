{ lib, ... }:
{
  # The Steam Deck runs Jovian's Gaming Mode (gamescope) and Plasma as its
  # desktop session — never niri. home/programs/linux-only is imported by
  # every Linux home config though, and noctalia's systemd user service is
  # bound to graphical-session.target, so without this the niri shell
  # autostarted inside Gaming Mode and the Plasma session.
  programs.noctalia.enable = lib.mkForce false;
  custom.niri.enable = lib.mkForce false;
}
