{
  pkgs,
  ...
}:
let
  suspendScript = pkgs.writeShellScriptBin "suspend-pre" ''
    playerctl pause
    lock-session
  '';

  resumeScript = pkgs.writeShellScriptBin "suspend-resume" ''
    niri msg action power-on-monitors
    bluetoothctl connect '88:C9:E8:06:5E:9C' && playerctl play
  '';
in
pkgs.stdenv.mkDerivation {
  dontUnpack = true;
  name = "suspendScripts";
  version = "1.0";

  installPhase = ''
    mkdir -p $out/bin
    cp ${suspendScript}/bin/suspend-pre $out/bin/
    cp ${resumeScript}/bin/suspend-resume $out/bin/
  '';
}
