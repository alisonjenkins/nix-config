{ pkgs
, ...
}: {
  # config.programs.hyprland.enable = true;
  wayland.windowManager.hyprland.systemd.enable = false;

  home.file =
    if pkgs.stdenv.isLinux then {
      ".config/hypr/conf/autostart.conf".text = import ./configs/hypr/conf/autostart.conf.nix { inherit pkgs; };
      ".config/hypr/conf/hyprlock.conf".text = import ./configs/hypr/conf/hyprlock.conf.nix;
      ".config/hypr/conf/keybinds.conf".text = import ./configs/hypr/conf/keybinds.conf.nix { inherit pkgs; };
      ".config/hypr/conf/windowrules.conf".text = import ./configs/hypr/conf/windowrules.conf.nix;
      ".config/hypr/conf/wleave-layout.conf".text = import ./configs/hypr/conf/wleave-layout.conf.nix { inherit pkgs; };
      ".config/hypr/hyprland.conf".text = builtins.readFile ./configs/hypr/hyprland.conf;
      ".config/xdg-desktop-portal/hyprland-portals.conf".text = builtins.readFile ./configs/xdg-desktop-portal/hyprland-portals.conf;
    } else { };
}
