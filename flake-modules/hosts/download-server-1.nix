{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.download-server-1 = lib.nixosSystem {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }
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
