{ pkgs, ... }: {
  # home.file = {
  #   ".config/eww/" = {
  #     recursive = true;
  #     source = ./eww;
  #   };
  # };

  home.packages = with pkgs; if pkgs.stdenv.hostPlatform.isLinux then [
    bc
    coreutils
    eww
    gnugrep
    wireplumber
  ] else [ ];
}
