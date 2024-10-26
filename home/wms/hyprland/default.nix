{ pkgs
, ...
}: {
  # config.programs.hyprland.enable = true;

  home.file = {
    ".config/hypr/conf/autostart.conf".text = import ./configs/hypr/conf/autostart.conf.nix { inherit pkgs; };
    ".config/hypr/conf/hyprlock.conf".text = import ./configs/hypr/conf/hyprlock.conf.nix;
    ".config/hypr/conf/keybinds.conf".text = import ./configs/hypr/conf/keybinds.conf.nix { inherit pkgs; };
    ".config/hypr/conf/wlogout-layout.conf".text = import ./configs/hypr/conf/wlogout-layout.conf.nix { inherit pkgs; };
    ".config/hypr/conf/windowrules.conf".text = import ./configs/hypr/conf/windowrules.conf.nix;
    ".config/hypr/hyprland.conf".text = builtins.readFile ./configs/hypr/hyprland.conf;
  };
}
