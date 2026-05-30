{ pkgs
, lib
, ...
}: {
  # home.file =
  #   if pkgs.stdenv.isLinux
  #   then {
  #     ".local/share/applications/OBS - Autostart Webcam.desktop".text = ''
  #       [Desktop Entry]
  #       Comment=
  #       Exec=obs --startvirtualcam
  #       GenericName=
  #       Icon=${pkgs.obs-studio}/share/icons/hicolor/512x512/apps/com.obsproject.Studio.png
  #       MimeType=
  #       Name=OBS Studio - Autostart Webcam
  #       Path=
  #       StartupNotify=true
  #       Terminal=false
  #       TerminalOptions=
  #       Type=Application
  #       X-KDE-SubstituteUID=false
  #       X-KDE-Username=
  #     '';
  #   }
  #   else { };

  programs.obs-studio = {
    enable = lib.mkIf pkgs.stdenv.isLinux true;
    plugins = with pkgs.obs-studio-plugins;
      [
        # unstable.advanced-scene-switcher
        droidcam-obs
        obs-backgroundremoval
        obs-pipewire-audio-capture
        obs-source-clone
        obs-vkcapture
      ]
      # looking-glass-obs is x86-only (depends on looking-glass which
      # itself relies on shared-memory IVSHMEM, a QEMU/x86 KVM feature).
      ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
        looking-glass-obs
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
