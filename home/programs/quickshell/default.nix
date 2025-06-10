{
  config,
  inputs,
  pkgs,
  system,
  ...
}:
let
  caelestia-shell = pkgs.stdenv.mkDerivation {
    name = "caelestia-shell";
    version = "0.1";

    buildPhase = ''
    cp -R . $out/
    '';

    src = pkgs.fetchFromGitHub {
      owner = "alisonjenkins";
      repo = "caelestia-shell";
      rev = "ea4d3f26ef438b8075d9ea1aa3f297173d6cd58d";
      sha256 = "sha256-rh4Cu24uZoArFBYJhREGPkwTFTA9Q2GeGjdOTu9WhgA=";
    };
  };
in
{
  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    ibm-plex
    inputs.quickshell.packages.${system}.default
    material-symbols
    nerd-fonts.jetbrains-mono
  ] else [];

  home.file = {
    ".config/quickshell/caelestia".source = config.lib.file.mkOutOfStoreSymlink "${caelestia-shell}";
  };
}
