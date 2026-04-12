{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-aws-tools;
in
{
  options.modules.desktop-aws-tools = {
    enable = lib.mkEnableOption "AWS desktop CLI tools (awscli2, aws-vault, git-remote-codecommit)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      aws-vault
      git-remote-codecommit
      awscli2
    ];
  };
}
