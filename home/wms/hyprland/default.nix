{
  inputs,
  pkgs,
  system,
  ...
}: let
  hyprevent = pkgs.writeShellScriptBin "hyprevent" ''
  case "''$1" in
    "lid")
      if ${pkgs.hyprland}/bin/hyprctl monitors | ${pkgs.gnugrep}/bin/grep -E "DP-[0-9]+" &>/dev/null; then
        if [[ "''$2" == "open" ]]; then
          ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-2,2560x1440@165,0x0,auto"
        else
          ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-2,disable"
        fi
        ${pkgs.procps}/bin/pkill -SIGUSR2 waybar;
      fi
      ;;
    "monitorUnplugged")
      # turn on internal monitor
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-2,2560x1440@165,0x0,auto"
      # reload waybar
      ${pkgs.procps}/bin/pkill -SIGUSR2 waybar;
    ;;
    "monitorPlugged")
      # turn off internal monitor
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-2,disable"
      # reload waybar
      ${pkgs.procps}/bin/pkill -SIGUSR2 waybar;
    ;;
    *)
      echo "Unknown event: ''$1 ''$2"
      exit 1
    ;;
  esac
  '';
in {
  services.hypridle.enable = true;
  wayland.windowManager.hyprland.systemd.enable = false;

  home.packages = with pkgs; if pkgs.stdenv.isLinux then [
    blueman
    hyprevent
    hyprlock
    hyprpolkitagent
    waypaper
  ] else [ ];

  home.file =
    if pkgs.stdenv.isLinux then {
      ".config/hypr/autostart.conf".text = import ./configs/hypr/autostart.conf.nix { inherit pkgs inputs system; };
      ".config/hypr/hypridle.conf".text = import ./configs/hypr/hypridle.conf.nix;
      ".config/hypr/hyprlock.conf".text = import ./configs/hypr/hyprlock.conf.nix;
      ".config/hypr/keybinds.conf".text = import ./configs/hypr/keybinds.conf.nix { inherit pkgs; };
      ".config/hypr/windowrules.conf".text = import ./configs/hypr/windowrules.conf.nix;
      ".config/hypr/wleave-layout.conf".text = import ./configs/hypr/wleave-layout.conf.nix { inherit pkgs; };
      ".config/hypr/hyprland.conf".text = builtins.readFile ./configs/hypr/hyprland.conf;
      ".config/hypr/hyprshade.toml".text = import ./configs/hypr/hyprshade.toml.nix;
      ".config/xdg-desktop-portal/hyprland-portals.conf".text = builtins.readFile ./configs/xdg-desktop-portal/hyprland-portals.conf;
    } else { };
}
