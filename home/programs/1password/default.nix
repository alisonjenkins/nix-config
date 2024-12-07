{ pkgs, ... }: {
  programs._1password-gui.enable = if pkgs.stdenv.isLinux then true else false;
  programs._1password-cli.enable = if pkgs.stdenv.isLinux then true else false;
}
