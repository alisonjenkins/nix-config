{ config
, pkgs
, lib
, inputs
, system
, ...
}: {
  home.packages = lib.optionals pkgs.stdenv.isLinux [
    pkgs.obsidian
  ];

  home.file =
    if pkgs.stdenv.isLinux && !builtins.pathExists /etc/NIXOS
    then {
      ".local/share/applications/Obsidian.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=${inputs.nixgl.packages.${system}.nixGLIntel}/bin/nixGLIntel ${pkgs.obsidian}/bin/obsidian
        GenericName[en_US]=
        GenericName=
        Icon=${pkgs.obsidian}/share/icons/hicolor/512x512/obsidian.png
        MimeType=
        Name[en_US]=Obsidian
        Name=Obsidian
        Path=
        StartupNotify=true
        Terminal=false
        TerminalOptions=
        Type=Application
        X-KDE-SubstituteUID=false
        X-KDE-Username=
      '';
    }
    else if config.programs.alacritty.enable && pkgs.stdenv.isLinux
    then {
      ".local/share/applications/Obsidian.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=${pkgs.obsidian}/bin/obsidian
        GenericName[en_US]=
        GenericName=
        Icon=${pkgs.obsidian}/share/icons/hicolor/512x512/obsidian.png
        MimeType=
        Name[en_US]=Obsidian
        Name=Obsidian
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
