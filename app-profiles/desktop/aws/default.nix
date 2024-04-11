{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    aws-vault
    git-remote-codecommit
    stable.awscli2
  ];
}
