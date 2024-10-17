{
  pkgs,
  config,
  ...
}: {
  # config.programs.hyprland.enable = true;

  home.file = {
    ".config/hypr/hyprland.conf".text = builtins.readFile ./configs/hypr/hyprland.conf;
    ".config/hypr/conf/keybinds.conf".text = import ./configs/hypr/conf/keybinds.conf.nix {inherit pkgs;};
    ".config/hypr/conf/wlogout-layout.conf".text = import ./configs/hypr/conf/wlogout-layout.conf.nix {inherit pkgs;};
    ".config/hypr/conf/hyprlock.conf".text = import ./configs/hypr/conf/hyprlock.conf.nix;
  };
}
