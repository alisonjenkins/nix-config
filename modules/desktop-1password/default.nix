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

    # gcr-ssh-agent and gnome-keyring's ssh component compete for SSH_AUTH_SOCK
    # in the systemd user environment. Mask them so 1Password's agent owns
    # SSH_AUTH_SOCK end-to-end.
    systemd.user.services.gcr-ssh-agent = lib.mkIf pkgs.stdenv.isLinux {
      enable = false;
      wantedBy = lib.mkForce [ ];
    };
    systemd.user.sockets.gcr-ssh-agent = lib.mkIf pkgs.stdenv.isLinux {
      enable = false;
      wantedBy = lib.mkForce [ ];
    };
  };
}
