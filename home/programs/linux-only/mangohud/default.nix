{ pkgs, ... }: {
  home.file = {
    ".config/MangoHud/MangoHud.conf".source = ./MangoHud.conf;
  };
}
