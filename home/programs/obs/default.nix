{ pkgs
, lib
, ...
}: {
  home.file =
    if pkgs.stdenv.isLinux
    then {
      ".local/share/applications/OBS - Autostart Webcam.desktop".text = ''
        [Desktop Entry]
        Comment=
        Exec=obs --startvirtualcam
        GenericName=
        Icon=${pkgs.obs-studio}/share/icons/hicolor/512x512/apps/com.obsproject.Studio.png
        MimeType=
        Name=OBS Studio - Autostart Webcam
        Path=
        StartupNotify=true
        Terminal=false
        TerminalOptions=
        Type=Application
        X-KDE-SubstituteUID=false
        X-KDE-Username=
      '';
    }
    else { };

  programs.obs-studio = {
    enable = lib.mkIf pkgs.stdenv.isLinux true;
    plugins = with pkgs.obs-studio-plugins;
      [
        # unstable.advanced-scene-switcher
        droidcam-obs
        looking-glass-obs
        obs-backgroundremoval
        obs-source-clone
        obs-vkcapture
      ];
  };

  home.packages = [
    (pkgs.writeShellScriptBin ''obs-browser'' ''
      ${pkgs.obs-do}/bin/obs-do set-scene "Browser"
    '')
    (pkgs.writeShellScriptBin ''obs-coding'' ''
      ${pkgs.obs-do}/bin/obs-do set-scene "Coding"
    '')
    (pkgs.writeShellScriptBin ''obs-droidcam'' ''
      ${pkgs.obs-do}/bin/obs-do set-scene "Droidcam"
    '')
    (pkgs.writeShellScriptBin ''obs-game-stream'' ''
      ${pkgs.obs-do}/bin/obs-do set-scene "Game Streaming"
    '')
    (pkgs.writeShellScriptBin ''obs-webcam'' ''
      ${pkgs.obs-do}/bin/obs-do set-scene "Webcam"
    '')
    (pkgs.writeShellScriptBin ''obs-webcam-bg'' ''
      ${pkgs.obs-do}/bin/obs-do set-scene "Webcam BG"
    '')
  ];
}
