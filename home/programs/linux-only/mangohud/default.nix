{ pkgs, inputs, system, config, ... }: {
  home.file = {
    ".config/MangoHud/MangoHud.conf".source = ./MangoHud.conf;
  };
}
