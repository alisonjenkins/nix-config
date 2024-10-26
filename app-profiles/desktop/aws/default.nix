{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    aws-vault
    git-remote-codecommit
    awscli2
  ];
}
