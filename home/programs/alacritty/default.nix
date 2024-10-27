{ config
, pkgs
, lib
, username
, inputs
, system
, ...
}: {
  home.packages = lib.optionals config.programs.alacritty.enable [ (pkgs.nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; }) ];

  home.file =
    if config.programs.alacritty.enable && pkgs.stdenv.isLinux && username == "deck"
    then {
      ".local/share/applications/Alacritty.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=${inputs.nixgl.packages.${system}.nixGLIntel}/bin/nixGLIntel ${pkgs.alacritty}/bin/alacritty
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
    }
    else if config.programs.alacritty.enable && pkgs.stdenv.isLinux
    then {
      ".local/share/applications/Alacritty.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=${pkgs.alacritty}/bin/alacritty
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
    }
    else { };

  programs.alacritty = {
    enable = true;

    settings = {
      font = {
        normal = {
          family = "FiraCode Nerd Font Mono";
          style = "Regular";
        };
        size = 12;
      };

      terminal = {
        shell = {
          program = "${pkgs.zsh}/bin/zsh";
          args = [
            "-l"
            "-c"
            "tmux attach ; tmux"
          ];
        };
      };

      mouse = {
        hide_when_typing = true;
      };

      window = {
        decorations = "None";
        opacity = 0.9;
        startup_mode = "Maximized";

        padding = {
          x = 12;
          y = 12;
        };
      };
    };
  };
}
