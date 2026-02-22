{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.home-k8s-server-1 = lib.nixosSystem rec {
    inherit system;
    specialArgs = {
      username = "ali";
      inherit inputs outputs system;
    };
    modules = [
      inputs.disko.nixosModules.disko
      ../../hosts/home-k8s-server-1/disko-config.nix
      ../../hosts/home-k8s-server-1/configuration.nix
    ];
  };
}
