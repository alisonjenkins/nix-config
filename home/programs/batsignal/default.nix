{ pkgs, ... }: {
  services.batsignal.enable = if pkgs.stdenv.hostPlatform.isLinux then true else false;
}
