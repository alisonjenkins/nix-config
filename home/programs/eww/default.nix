{ pkgs, ... }: {
  # home.file = {
  #   ".config/eww/" = {
  #     recursive = true;
  #     source = ./eww;
  #   };
  # };

  home.packages = with pkgs; if pkgs.stdenv.isLinux then [
    bc
    coreutils
    eww
    gnugrep
    wireplumber
  ] else [ ];
}
