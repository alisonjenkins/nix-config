{ pkgs
, lib
, system
, inputs
, ...
}: {
  home.file =
    if pkgs.stdenv.isLinux
    then {
      ".local/share/applications/OBS - Autostart Webcam.desktop".text = ''
        [Desktop Entry]
        Comment=
        Exec=${pkgs.obs-studio}/bin/obs --startvirtualcam
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
}
