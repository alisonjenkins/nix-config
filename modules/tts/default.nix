{ config, lib, pkgs, ... }:
let
  cfg = config.modules.tts;
in
{
  options.modules.tts = {
    enable = lib.mkEnableOption "text-to-speech via Piper";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.piper-tts-talk
    ];
  };
}
