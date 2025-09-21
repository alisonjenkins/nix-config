{ pkgs, ... }: {
  home.packages = with pkgs; [
    # localstack
    aws-sam-cli
    awscli2
    ec2-metadata-mock
    git-remote-codecommit
    packer
  ];
}
