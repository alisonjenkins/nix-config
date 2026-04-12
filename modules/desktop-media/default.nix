{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-media;
in
{
  options.modules.desktop-media = {
    enable = lib.mkEnableOption "media playback tools (mpv, vlc)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mpv
      vlc
    ];
  };
}
