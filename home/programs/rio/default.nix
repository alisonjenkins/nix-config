{ pkgs
, ...
}:
{
  home.file = {
    ".config/rio/config.toml".text = builtins.readFile ./config.toml;
  };
}
