{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = lib.optionals config.programs.alacritty.enable [(pkgs.nerdfonts.override {fonts = ["FiraCode" "Hack" "JetBrainsMono"];})];

  programs.alacritty = {
    enable = true;

    settings = {
      font = {
        normal = {
          family = "Hack Nerd Font Mono";
          style = "Regular";
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
        program = "${pkgs.zsh}/bin/zsh";
        args = [
          "-l"
          "-c"
          "tmux attach ; tmux"
        ];
      };
    };
  };
}
