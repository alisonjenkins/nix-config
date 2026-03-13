{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.home-k8s-server-1 = lib.nixosSystem {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }
      inputs.disko.nixosModules.disko
      ../../hosts/home-k8s-server-1/disko-config.nix
      ../../hosts/home-k8s-server-1/configuration.nix
    ];
  };
}
