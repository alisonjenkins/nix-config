{ config
, pkgs
, lib
, username
, inputs
, system
, ...
}: {
  home.packages = lib.optionals config.programs.alacritty.enable [
    pkgs.nerd-fonts.fira-code
    pkgs.nerd-fonts.hack
    pkgs.nerd-fonts.jetbrains-mono
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
    }
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
    }
    else { };

  programs.alacritty = {
    enable = true;

    settings = {
      # font = {
      #   normal = {
      #     family = "FiraCode Nerd Font Mono";
      #     style = "Regular";
      #   };
      #   size = 12;
      # };

      terminal = {
        osc52 = "CopyPaste";
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
        # opacity = 0.9;
        # startup_mode = "Maximized";
      };
    };
  };
}
