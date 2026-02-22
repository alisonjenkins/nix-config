{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.home-k8s-master-1 = lib.nixosSystem rec {
    inherit system;
    specialArgs = {
      username = "ali";
      inherit inputs outputs system;
    };
    modules = [
      ../../hosts/home-k8s-master-1/configuration.nix
      ../../hosts/home-k8s-master-1/hardware-configuration.nix
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
    ];
  };
}
