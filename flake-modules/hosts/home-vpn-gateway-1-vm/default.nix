{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
in {
  flake.nixosConfigurations.home-vpn-gateway-1-vm = lib.nixosSystem {
    specialArgs = {
      username = "ali";
      inherit inputs;
      inherit (self) outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs (shared with regular host)
      self.nixosModules.locale
      self.nixosModules.base
      self.nixosModules.amnezia-vpn-gateway
      self.nixosModules.home-vpn-gateway-1-hardware

      # VM-specific disko config (replaces regular disko)
      self.nixosModules.home-vpn-gateway-1-vm-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops

      ({ config, inputs, lib, outputs, pkgs, ... }: {
        modules.base = {
          enable = true;
          enableImpermanence = true;
        };
        modules.locale.enable = true;

        console.keyMap = "us";
        programs.zsh.enable = true;
        time.timeZone = "Europe/London";

        boot = {
          kernelPackages = pkgs.linuxPackages_latest;
          kernelParams = [
            "irqpoll"
          ];
        };

        environment = {
          pathsToLink = [ "/share/zsh" ];

          systemPackages = with pkgs; [
            amneziawg-tools
            privoxy
          ];

          variables = {
            PATH = [
              "\${HOME}/.local/bin"
              "\${HOME}/.config/rofi/scripts"
            ];
          };
        };

        networking = {
          hostName = "home-vpn-gateway-1";
          networkmanager.enable = true;

          firewall = {
            enable = true;
            allowPing = true;

            allowedTCPPorts = [
              22
              8118
            ];
            allowedUDPPorts = [];
          };
        };

        services = {
          logrotate.checkConfig = false;

          privoxy = {
            enable = true;
            enableTor = true;

            settings = {
              listen-address = "0.0.0.0:8118";
              forward-socks5 = lib.mkForce ".onion localhost:9050 .";
            };
          };

          amneziaVpnGateway = {
            enable = true;

            network = {
              lanInterfaces = [ "enp1s0" "tailscale0" ];
              lanSubnets = [ "192.168.1.0/24" ];
              vpnGatewayIp = "192.168.1.1";
            };

            vpn = {
              interface = "awg0";
              configFile = "/persistence/etc/amnezia-wg/client.conf";
              serverIp = "62.210.188.244";
              serverPort = 255;

              amnezia = {
                junkPacketCount = 4;
                junkPacketMinSize = 50;
                junkPacketMaxSize = 1000;
                initPacketJunkSize = 200;
                responsePacketJunkSize = 200;
                initPacketMagicHeader = 1234567890;
                responsePacketMagicHeader = 987654321;
                underloadPacketMagicHeader = 1122334455;
                transportPacketMagicHeader = 5544332211;
              };
            };

            dns = {
              localPort = 5353;
              upstreamServers = [
                "149.112.112.112"
                "9.9.9.9"
                "1.1.1.1"
              ];
            };

            firewall = {
              allowedTCPPorts = [ 22 8118 ];
              logLevel = "warn";
            };

            monitoring = {
              enable = true;
              checkInterval = "5min";
              killSwitchTimeout = 30;
            };
          };
        };

        system = {
          stateVersion = "24.05";
        };

        security = {
          sudo = {
            wheelNeedsPassword = lib.mkForce false;
          };
        };

        users = {
          users = {
            ali = {
              description = "Alison Jenkins";
              extraGroups = [ "docker" "networkmanager" "wheel" ];
              hashedPasswordFile = "/persistence/passwords/ali";
              isNormalUser = true;
              openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];
            };
            root = {
              hashedPasswordFile = "/persistence/passwords/root";
            };
          };
        };
      })

      # VM-specific overrides
      {
        services.amneziaVpnGateway.vpn.configFile = lib.mkForce "/etc/amnezia-wg/client.conf";

        # For VM testing, disable password files and use direct hashes
        users.users.ali = {
          hashedPasswordFile = lib.mkForce null;
          hashedPassword = lib.mkForce "$y$j9T$kSKqHpK7ynHB61Wb37azQ1$o/.rzd8LeVp6XrUdoVlxU87KcGhvubfATwwclEWG527";
        };
        users.users.root = {
          hashedPasswordFile = lib.mkForce null;
          hashedPassword = lib.mkForce "$y$j9T$kSKqHpK7ynHB61Wb37azQ1$o/.rzd8LeVp6XrUdoVlxU87KcGhvubfATwwclEWG527";
        };

        # Enable autologin for easier VM testing
        services.getty.autologinUser = lib.mkForce "ali";

        # Also enable root SSH access
        services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
      }
    ];
  };
}
