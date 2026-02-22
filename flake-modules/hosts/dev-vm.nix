{ inputs, self, ... }:
let
  system = "aarch64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.dev-vm = lib.nixosSystem rec {
    inherit system;
    specialArgs = {
      username = "ali";
      inherit inputs outputs system;
    };
    modules = [
      ../../hosts/dev-vm/configuration.nix
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
    ];
  };
}
