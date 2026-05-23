{ pkgs, aws_region ? "eu-west-1", ... }:
{
  AWS_DEFAULT_REGION = aws_region;
  ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";

  # Firefox/Mozilla optimizations
  MOZ_ENABLE_WAYLAND = "1";  # Enable Wayland support for Firefox
  MOZ_USE_XINPUT2 = "1";     # Better touchpad/input support

  # VA-API hardware acceleration for AMD GPUs
  LIBVA_DRIVER_NAME = "radeonsi";  # AMD VA-API driver
}
// (
  if pkgs.stdenv.isLinux
  then {
    SSH_AUTH_SOCK = "\${HOME}/.1password/agent.sock";
  }
  else if pkgs.stdenv.isDarwin
  then {
    SSH_AUTH_SOCK = "\${HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  }
  else { }
)
