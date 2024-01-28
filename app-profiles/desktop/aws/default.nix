{ pkgs, inputs, system, ... }:
{

  environment.systemPackages = with pkgs; [
    awscli2
    aws-vault
    git-remote-codecommit
  ];
}
