{ pkgs, ... }: {
  home.packages = [
    # zed was renamed super in nixpkgs 26.11; it ships `super`, not `zq`.
    pkgs.super
  ];
}
