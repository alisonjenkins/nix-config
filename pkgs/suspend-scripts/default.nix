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
    RECONNECT_BLUETOOTH_MAC="''${1:}"
    niri msg action power-on-monitors

    if [[ "$RECONNECT_BLUETOOTH_MAC" ]]; then
      bluetoothctl connect "$RECONNECT_BLUETOOTH_MAC" && playerctl play
    fi
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
