{...}: {
  programs.starship = {
    enable = false;
  };

  home.file = {
    ".config/starship/config.toml".text = builtins.readFile ./config.toml;
  };
}
