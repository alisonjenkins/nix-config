{ pkgs
, ...
}: {
  # keybase-gui has no aarch64 build; skip the gui on arm Linux.
  home.packages =
    if pkgs.stdenv.isLinux && pkgs.stdenv.hostPlatform.isx86_64 then
      with pkgs; [ keybase keybase-gui ]
    else if pkgs.stdenv.isLinux then
      with pkgs; [ keybase ]
    else [];

  # home.file =
  #   if pkgs.stdenv.isLinux then {
  #     ".local/share/applications/Keybase.desktop".text = ''
  #       [Desktop Entry]
  #       Comment[en_US]=
  #       Comment=
  #       Exec=${pkgs.keybase-gui}/bin/keybase-gui
  #       GenericName[en_US]=
  #       GenericName=
  #       Icon=${pkgs.keybase-gui}/share/icons/hicolor/128x128/apps/keybase.png
  #       MimeType=
  #       Name[en_US]=Keybase
  #       Name=Keybase
  #       Path=
  #       StartupNotify=true
  #       Terminal=false
  #       TerminalOptions=
  #       Type=Application
  #       X-KDE-SubstituteUID=false
  #       X-KDE-Username=
  #     '';
  #   } else { };
}

