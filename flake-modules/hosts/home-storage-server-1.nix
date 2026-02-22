{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.home-storage-server-1 = lib.nixosSystem rec {
    inherit system;
    specialArgs = {
      username = "ali";
      inherit inputs outputs system;
    };
    modules = [
      ../../hosts/home-storage-server-1/configuration.nix
      ../../hosts/home-storage-server-1/disko-config.nix
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
    ];
  };
}
