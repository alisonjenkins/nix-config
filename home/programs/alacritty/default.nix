{ config
, pkgs
, lib
, username
, inputs
, system
, ...
}:
let
  alacritty_config = {
    ".config/alacritty/alacritty.toml" = (import ./alacritty.toml.nix {inherit pkgs;});
  };
in {
  home.packages = lib.optionals config.programs.alacritty.enable [
        pkgs.nerd-fonts.fira-code
        pkgs.nerd-fonts.hack
        pkgs.nerd-fonts.jetbrains-mono
        pkgs.recursive
  ];

  home.file =
    if config.programs.alacritty.enable && pkgs.stdenv.isLinux && username == "deck"
    then {
      ".local/share/applications/Alacritty.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=${inputs.nixgl.packages.${system}.nixGLIntel}/bin/nixGLIntel alacritty
        GenericName[en_US]=
        GenericName=
        Icon=${pkgs.alacritty}/share/icons/hicolor/scalable/apps/Alacritty.svg
        MimeType=
        Name[en_US]=Alacritty
        Name=Alacritty
        Path=
        StartupNotify=true
        Terminal=false
        TerminalOptions=
        Type=Application
        X-KDE-SubstituteUID=false
        X-KDE-Username=
      '';
    } // alacritty_config
    else if config.programs.alacritty.enable && pkgs.stdenv.isLinux
    then {
      ".local/share/applications/Alacritty.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=alacritty
        GenericName[en_US]=
        GenericName=
        Icon=${pkgs.alacritty}/share/icons/hicolor/scalable/apps/Alacritty.svg
        MimeType=
        Name[en_US]=Alacritty
        Name=Alacritty
        Path=
        StartupNotify=true
        Terminal=false
        TerminalOptions=
        Type=Application
        X-KDE-SubstituteUID=false
        X-KDE-Username=
      '';
    } // alacritty_config
    else { };
}
