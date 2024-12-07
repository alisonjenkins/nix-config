{ pkgs, ... }: {
  home.packages =
    if pkgs.stdenv.isLinux
    then
      with pkgs; [
        _1password-cli
        _1password-gui
      ]
    else [ ];

  home.file =
    if pkgs.stdenv.isLinux
    then {
      ".local/share/applications/1Password.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=${pkgs._1password-gui}/bin/1password
        GenericName[en_US]=
        GenericName=
        Icon=${pkgs._1password-gui}/share/icons/hicolor/512x512/apps/1password.png
        MimeType=
        Name[en_US]=1Password
        Name=1Password
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
}
