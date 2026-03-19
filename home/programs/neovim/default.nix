{ inputs
, pkgs
, ...
}: {
  home.packages = [
    inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.nvim
  ];
}
