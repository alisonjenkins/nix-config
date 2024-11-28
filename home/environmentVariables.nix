{ aws_region ? "eu-west-1", ... }:
{
  AWS_DEFAULT_REGION = aws_region;
  ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
}
