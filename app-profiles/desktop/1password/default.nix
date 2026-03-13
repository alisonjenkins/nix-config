{ pkgs, config, lib, ... }: {
  programs._1password-gui = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    package = pkgs.unstable._1password-gui;
    polkitPolicyOwners = builtins.attrNames config.users;
  };

  programs._1password = {
    enable = pkgs.stdenv.isLinux;
    package = pkgs.unstable._1password-cli;
  };
}
