{ inputs
, pkgs
, ...
}: {
  custom.homePackages = [
    inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.nvim
  ];
}
