{ aws_region ? "eu-west-1", ... }:
{
  AWS_DEFAULT_REGION = aws_region;
  ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";

  # Firefox/Mozilla optimizations
  MOZ_ENABLE_WAYLAND = "1";  # Enable Wayland support for Firefox
  MOZ_USE_XINPUT2 = "1";     # Better touchpad/input support

  # VA-API hardware acceleration for AMD GPUs
  LIBVA_DRIVER_NAME = "radeonsi";  # AMD VA-API driver
}
