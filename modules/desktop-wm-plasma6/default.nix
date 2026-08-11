{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-wm-plasma6;
in
{
  options.modules.desktop-wm-plasma6 = {
    enable = lib.mkEnableOption "KDE Plasma 6 desktop environment";
  };

  config = lib.mkMerge [
    # Keyed on the upstream option rather than on `cfg.enable`, so hosts that
    # turn Plasma on directly (ali-steam-deck sets
    # `services.desktopManager.plasma6.enable` itself, because it also runs
    # Jovian's Gaming Mode and must not take our `displayManager.defaultSession
    # = "plasma"`) are covered too.
    (lib.mkIf (config.services.desktopManager.plasma6.enable && config ? home-manager) {
      # Stylix's qt target defaults to platform "qtct", which exports
      # QT_STYLE_OVERRIDE=kvantum. Plasma's QtQuick Controls resolve the
      # widget-style name as a QML module, so with kvantum forced every Plasma
      # QML component fails to load and the session comes up with no shell UI:
      #
      #   plasmashell: ImageStackView.qml: module "kvantum" is not installed
      #   plasmashell: QQmlComponent: Component is not ready
      #
      # Plasma themes itself via Breeze (and stylix's own kde target), so the
      # qt target has nothing to contribute here. mkDefault keeps it
      # overridable per host.
      home-manager.sharedModules = [
        { stylix.targets.qt.enable = lib.mkDefault false; }
      ];
    })

    (lib.mkIf cfg.enable {
    environment.sessionVariables = {
      NIX_PROFILES = "${pkgs.lib.concatStringsSep " " (pkgs.lib.reverseList config.environment.profiles)}";
    };

    programs.dconf.enable = true;
    environment.systemPackages = with pkgs; [
      kdePackages.qtbase.out
      kdePackages.plasma-browser-integration
    ];

    services = {
      desktopManager = {
        plasma6 = {
          enable = true;
        };
      };
      displayManager.defaultSession = "plasma";
    };
    })
  ];
}
