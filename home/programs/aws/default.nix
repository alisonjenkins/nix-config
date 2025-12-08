{ pkgs, ... }: {
  home.packages = with pkgs; [
    # localstack
    # aws-sam-cli  # Temporarily disabled due to dependency conflicts in 25.11
    awscli2
    ec2-metadata-mock
    git-remote-codecommit
    packer
  ];
}
