{ inputs
, pkgs
, osConfig ? null
, ...
}: {
  # On NixOS, nixvim is installed system-wide via modules/base or app-profiles/desktop/base.
  # Only install via home-manager for non-NixOS systems (standalone home-manager, Darwin).
  home.packages = pkgs.lib.mkIf (osConfig == null) [
    inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.nvim
  ];
}
