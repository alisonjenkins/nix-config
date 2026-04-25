{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
in {
  flake.nixosConfigurations.home-kvm-hypervisor-1 = lib.nixosSystem {
    specialArgs = {
      username = "ali";
      inherit inputs;
      inherit (self) outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.locale
      self.nixosModules.base
      self.nixosModules.nohang
      self.nixosModules.servers
      self.nixosModules.libvirtd
      self.nixosModules.home-kvm-hypervisor-1-hardware
      self.nixosModules.home-kvm-hypervisor-1-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.nixvirt.nixosModules.default
      inputs.sops-nix.nixosModules.sops

      # Host-specific configuration
      ({ inputs, lib, outputs, pkgs, ... }: {
        modules.nohang = {
          enable = true;
          extraProtectedProcesses = [ "libvirtd" "qemu-system-x86_64" ];
        };
        modules.base = {
          enable = true;
          bootLoader = "grub";
        };
        modules.libvirtd.enable = true;
        modules.locale.enable = true;
        modules.servers = {
          enable = true;
          prometheus.smartctlExporter.enable = true;
          prometheus.libvirtExporter.enable = true;
        };

        boot = {
          kernelPackages = pkgs.linuxPackages_latest;

          kernelParams = [
            # SAS3008 controllers (1000:0097) bound early via vfio-pci — prevents mpt3sas from claiming them
            # GPU (1002:164e) stays on amdgpu for LUKS prompt; libvirt rebinds it when VM starts (managed='yes')
            "vfio-pci.ids=1000:0097"
            "systemd.gpt_auto=no"
          ];

          kernel = {
            sysctl = {
              "net.ipv4.conf.all.forwarding" = true;
              "net.ipv6.conf.all.forwarding" = true;
            };
          };

          initrd = {
            availableKernelModules = [
              "ixgbe"
              "mt7921e"
              "r8169"
            ];
          };
        };

        console.keyMap = "us";

        environment = {
          pathsToLink = [ "/share/zsh" ];

          variables = {
            PATH = [
              "\${HOME}/.local/bin"
              "\${HOME}/.config/rofi/scripts"
            ];
          };
        };

        networking = {
          hostName = "home-kvm-hypervisor-1";
          networkmanager.enable = lib.mkForce false;
          useDHCP = false;
        };

        programs = {
          zsh.enable = true;
        };

        time = {
          timeZone = "Europe/London";
        };

        users.users.ali = {
          isNormalUser = true;
          description = "Alison Jenkins";
          initialPassword = "initPw!";
          extraGroups = [ "docker" "libvirtd" "wheel" ];
          openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];
        };

        security = {
          sudo = {
            wheelNeedsPassword = lib.mkForce false;
          };
        };

        system.stateVersion = "24.05";

        systemd = {

          network = {
            enable = true;

            netdevs = {
              "20-br0" = {
                netdevConfig = {
                  Kind = "bridge";
                  Name = "br0";
                };
              };
            };

            networks = {
              "30-enp16s0" = {
                matchConfig.Name = "enp16s0";
                networkConfig = {
                  Bridge = "br0";
                };
                linkConfig = {
                  RequiredForOnline = "enslaved";
                };
              };

              "40-br0" = {
                DHCP = "yes";
                matchConfig.Name = "br0";
                bridgeConfig = {};
                dhcpV4Config = { UseDNS = true; UseRoutes = true; };
                linkConfig = {
                  RequiredForOnline = "routable";
                };
              };
            };
          };
        };

        virtualisation = {
          libvirtd = {
            package = inputs.nixpkgs_old.legacyPackages.${pkgs.stdenv.hostPlatform.system}.libvirt;
            qemu = {
              package = lib.mkForce inputs.nixpkgs_old.legacyPackages.${pkgs.stdenv.hostPlatform.system}.qemu;
              runAsRoot = true;
              swtpm.enable = true;
            };
          };

          libvirt = {
            enable = true;
            package = inputs.nixpkgs_old.legacyPackages.${pkgs.stdenv.hostPlatform.system}.libvirt;

            connections = {
              "qemu:///system" = {
                domains = [
                  {
                    active = true;
                    definition = pkgs.writeText "download-server-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/download-server-1.xml.nix") {inherit pkgs;});
                  }
                  {
                    active = true;
                    definition = pkgs.writeText "home-k8s-master-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/home-k8s-master-1.xml.nix") {inherit pkgs;});
                  }
                  {
                    active = true;
                    definition = pkgs.writeText "home-storage-server-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/home-storage-server-1.xml.nix") {inherit pkgs;});
                  }
                  {
                    active = true;
                    definition = pkgs.writeText "home-vpn-gateway-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/home-vpn-gateway-1.xml.nix") {inherit pkgs;});
                  }
                  # {
                  #   active = true;
                  #   definition = pkgs.writeText "Unraid.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/Unraid.xml.nix") {inherit pkgs;});
                  # }
                ];

                networks = [
                  {
                    active = true;
                    definition = pkgs.writeText "kvm-networks.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/networks/default.xml.nix"));
                  }
                ];

                pools = [
                  {
                    definition = self + "/libvirtd/home-kvm-hypervisor-1/pools/default.xml";

                    # volumes = [
                    # ];
                  }
                ];
              };
            };
          };
        };
      })
    ];
  };
}
