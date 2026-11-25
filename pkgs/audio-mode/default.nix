{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "audio-mode";
  runtimeInputs = with pkgs; [
    coreutils
    gnugrep
    jq
    libnotify
    pulseaudio
  ];
  text = builtins.readFile ./audio-mode.sh;
  meta = {
    description = "Switch audio between the Steam Frame and the desk setup";
    mainProgram = "audio-mode";
  };
}
