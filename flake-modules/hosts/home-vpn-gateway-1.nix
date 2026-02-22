{ inputs, self, lib, ... }:
let
  system = "x86_64-linux";
  nixLib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations = {
    home-vpn-gateway-1 = nixLib.nixosSystem rec {
      inherit system;
      specialArgs = {
        username = "ali";
        inherit inputs outputs system;
      };
      modules = [
        ../../hosts/home-vpn-gateway-1/configuration.nix
        ../../hosts/home-vpn-gateway-1/hardware-configuration.nix
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
      ];
    };

    home-vpn-gateway-1-vm = nixLib.nixosSystem rec {
      inherit system;
      specialArgs = {
        username = "ali";
        inherit inputs outputs system;
      };
      modules = [
        ../../hosts/home-vpn-gateway-1/configuration.nix
        ../../hosts/home-vpn-gateway-1/hardware-configuration.nix
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        {
          # Import VM-specific disko configuration
          imports = [ ../../hosts/home-vpn-gateway-1/vm-disko-config.nix ];

          # Override the default disko config
          disabledModules = [ ../../hosts/home-vpn-gateway-1/disko-config.nix ];

          # VM-specific overrides
          services.amneziaVpnGateway.vpn.configFile = nixLib.mkForce "/etc/amnezia-wg/client.conf";

          # For VM testing, disable password files and use direct hashes
          users.users.ali = {
            hashedPasswordFile = nixLib.mkForce null;
            hashedPassword = nixLib.mkForce "$y$j9T$kSKqHpK7ynHB61Wb37azQ1$o/.rzd8LeVp6XrUdoVlxU87KcGhvubfATwwclEWG527";
          };
          users.users.root = {
            hashedPasswordFile = nixLib.mkForce null;
            hashedPassword = nixLib.mkForce "$y$j9T$kSKqHpK7ynHB61Wb37azQ1$o/.rzd8LeVp6XrUdoVlxU87KcGhvubfATwwclEWG527";
          };

          # Enable autologin for easier VM testing
          services.getty.autologinUser = nixLib.mkForce "ali";

          # Also enable root SSH access
          services.openssh.settings.PermitRootLogin = nixLib.mkForce "yes";
        }
      ];
    };
  };
}
