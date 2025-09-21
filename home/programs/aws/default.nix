{ pkgs, ... }: {
  home.packages = with pkgs; [
    # aws-sam-cli
    awscli2
    ec2-metadata-mock
    git-remote-codecommit
  ];
}
