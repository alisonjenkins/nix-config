{ pkgs, ... }: {
  home.packages = [ pkgs.audio-mode ];

  custom.niri.extraBinds = ''
    Mod+Shift+A hotkey-overlay-title="Audio: Steam Frame / desk" { spawn "audio-mode" "toggle"; }
  '';
}
