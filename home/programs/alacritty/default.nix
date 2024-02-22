{ config, pkgs, lib, ... }: {
  home.packages = lib.optionals config.programs.alacritty.enable [ pkgs.nerdfonts ];

  programs.alacritty = {
    enable = true;

    settings = {
      font = {
        normal = {
          family = "Hack";
          style = "Medium";
        };
        size = 12;
      };

      window = {
        padding = {
          x = 12;
          y = 12;
        };
      };
      shell = {
        program = "${pkgs.nushell}/bin/nu";
        args = [
          "-l"
          "-e"
          "tmux attach ; tmux"
        ];
      };
    };
  };
}

