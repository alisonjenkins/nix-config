{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-1password;
in
{
  options.modules.desktop-1password = {
    enable = lib.mkEnableOption "1Password CLI and GUI";
  };

  config = lib.mkIf cfg.enable {
    programs._1password-gui = lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
      package = pkgs._1password-gui;
      polkitPolicyOwners = builtins.attrNames config.users;
    };

    programs._1password = {
      enable = pkgs.stdenv.isLinux;
      package = pkgs._1password-cli;
    };
  };
}
