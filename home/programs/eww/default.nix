{ pkgs, ... }: {
  home.file = {
    ".config/eww/" = {
      recursive = true;
      source = ./eww;
    };
  };

  home.packages = with pkgs; [
    bc
    coreutils
    eww
    gnugrep
    wireplumber
  ];
}
