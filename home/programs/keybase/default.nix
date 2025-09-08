{ pkgs
, ...
}: {
  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    keybase
    keybase-gui
  ] else [];

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

