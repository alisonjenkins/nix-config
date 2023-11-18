{ config, pkgs, ... }:

{
  programs = {
    zsh = {
      enable = true;
      autocd = true;
      enableAutosuggestions = true;
      defaultKeymap = "viins";
      initExtraBeforeCompInit = builtins.readFile ./zshrc.sh;

      history = {
        size = 999999;
        save = 999999;
        path = "$HOME/.local/share/zsh/history";
        extended = true;
      };

      plugins = [
        {
          name = "tipz";
          src = pkgs.fetchFromGitHub {
            owner = "molovo";
            repo = "tipz";
            rev = "master";
            sha256 = "oFZJwHYDfK4f53lhcZg6PCw2AgHxFC0CRiqiinKZz8k=";
          };
        }
      ];
    };
  };

  home.file = {
    ".local/share/zsh/.keep".text = "";
    ".config/zshrc.d" = {
      source = ./zshrc.d;
      recursive = true;
    };
  };
}

