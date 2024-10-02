{pkgs, ...}: {
  home.packages = [
    pkgs.rust-bin.stable.latest.default
    pkgs.bacon
  ];
}
