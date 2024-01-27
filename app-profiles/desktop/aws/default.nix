{ pkgs, inputs, system, ... }:
{

  environment.systemPackages = with pkgs; [
    aws-vault
    git-remote-codecommit
  ];
}
