{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.download-server-1 = lib.nixosSystem rec {
    inherit system;
    specialArgs = {
      username = "ali";
      inherit inputs outputs system;
    };
    modules = [
      ../../hosts/download-server-1/configuration.nix
      ../../hosts/download-server-1/hardware-configuration.nix
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      {
        nixpkgs.overlays = [
          self.overlays.qbittorrent
        ];
      }
    ];
  };
}
