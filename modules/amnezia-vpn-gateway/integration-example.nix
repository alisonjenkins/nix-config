# Integration example for Amnezia VPN Gateway module
# This shows how to add the module to your NixOS configuration

{
  # Method 1: Direct import in configuration.nix
  direct-import = {
    imports = [
      ./modules/amnezia-vpn-gateway
    ];

    services.amneziaVpnGateway = {
      enable = true;
      
      network = {
        lanInterfaces = [ "enp3s0" ];
        lanSubnets = [ "192.168.1.0/24" ];
        vpnGatewayIp = "192.168.1.1";
      };

      vpn = {
        interface = "awg0";
        configFile = "/etc/amnezia-wg/client.conf";
        serverIp = "vpn.example.com";
      };
    };
  };

  # Method 2: Flake-based configuration
  flake-based = {
    # In your flake.nix, add the module to your system configuration:
    
    nixosConfigurations.your-vpn-gateway = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./modules/amnezia-vpn-gateway
        {
          services.amneziaVpnGateway = {
            enable = true;
            
            network = {
              lanInterfaces = [ "enp3s0" ];
              lanSubnets = [ "192.168.1.0/24" ];
              vpnGatewayIp = "192.168.1.1";
            };

            vpn = {
              interface = "awg0";
              configFile = "/etc/amnezia-wg/client.conf";
              serverIp = "vpn.example.com";
            };
          };
        }
      ];
    };
  };

  # Method 3: Module registry (if you want to make it available system-wide)
  module-registry = {
    # In your /etc/nixos/configuration.nix or flake
    nix.nixPath = [
      "nixos-config=/etc/nixos/configuration.nix"
      "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
      "amnezia-vpn-gateway=/path/to/your/nix-config/modules/amnezia-vpn-gateway"
    ];

    # Then you can import it as:
    imports = [
      <amnezia-vpn-gateway>
    ];
  };

  # Method 4: With nixos-option for testing
  testing-config = {
    # You can test the module options without applying:
    # nixos-option -I nixos-config=./test-config.nix services.amneziaVpnGateway

    imports = [
      ./modules/amnezia-vpn-gateway
    ];

    services.amneziaVpnGateway = {
      enable = false; # Set to false for testing options only
      
      network = {
        lanInterfaces = [ "eth0" ];
        lanSubnets = [ "10.0.0.0/24" ];
        vpnGatewayIp = "10.0.0.1";
      };

      vpn = {
        interface = "awg0";
        configFile = "/tmp/test.conf";
        serverIp = "test.example.com";
      };
    };
  };
}