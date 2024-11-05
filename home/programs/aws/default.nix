{ pkgs, ... }: {
  home.packages = with pkgs; [
    # aws-sam-cli
    awscli2
    git-remote-codecommit
  ];
}
