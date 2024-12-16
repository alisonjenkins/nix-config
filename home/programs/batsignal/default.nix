{ pkgs, ... }: {
  services.batsignal.enable = if pkgs.stdenv.isLinux then true else false;
}
