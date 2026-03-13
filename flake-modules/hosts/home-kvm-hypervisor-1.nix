{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.home-kvm-hypervisor-1 = lib.nixosSystem {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }
      ../../hosts/home-kvm-hypervisor-1/configuration.nix
      ../../hosts/home-kvm-hypervisor-1/disko-config.nix
      inputs.disko.nixosModules.disko
      inputs.nixvirt.nixosModules.default
      inputs.sops-nix.nixosModules.sops
    ];
  };
}
