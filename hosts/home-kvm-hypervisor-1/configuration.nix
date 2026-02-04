{ pkgs
, inputs
, outputs
, lib
, ...
}: {
  imports = [
    # ../../app-profiles/server-base/luks-tor-unlock
    (import ../../modules/locale { })
    (import ../../app-profiles/kvm-server {inherit pkgs;})
    (import ../../modules/base {
      enableImpermanence = false;
      enablePlymouth = false;
      useGrub = true;
      useSystemdBoot = false;
      inherit inputs lib outputs pkgs;
    })
    (import ../../modules/servers {
      enablePrometheusSmartctlExporter = true;
      enablePrometheusLibvirtExporter = true;
    })
    ./hardware-configuration.nix
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;

    kernelParams = [
      "vfio-pci.ids=1000:0072,1002:164e"
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
    extraGroups = [ "docker" "libvirtd" "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
  };

  nix = {
    package = pkgs.nixVersions.stable;

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };

    settings = {
      auto-optimise-store = false;
      trusted-users = [ "root" "@wheel" ];
    };
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
      package = inputs.nixpkgs_old.legacyPackages.${pkgs.system}.libvirt;
      qemu = {
        package = inputs.nixpkgs_old.legacyPackages.${pkgs.system}.qemu;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };

    libvirt = {
      enable = true;
      package = inputs.nixpkgs_old.legacyPackages.${pkgs.system}.libvirt;

      connections = {
        "qemu:///system" = {
          domains = [
            {
              active = true;
              definition = pkgs.writeText "download-server-1.xml" (import ./libvirtd/domains/download-server-1.xml.nix {inherit pkgs;});
            }
            {
              active = true;
              definition = pkgs.writeText "home-k8s-master-1.xml" (import ./libvirtd/domains/home-k8s-master-1.xml.nix{inherit pkgs;});
            }
            {
              active = true;
              definition = pkgs.writeText "home-storage-server-1.xml" (import ./libvirtd/domains/home-storage-server-1.xml.nix {inherit pkgs;});
            }
            {
              active = true;
              definition = pkgs.writeText "home-vpn-gateway-1.xml" (import ./libvirtd/domains/home-vpn-gateway-1.xml.nix {inherit pkgs;});
            }
            # {
            #   active = true;
            #   definition = pkgs.writeText "Unraid.xml" (import ./libvirtd/domains/Unraid.xml.nix {inherit pkgs;});
            # }
          ];

          networks = [
            {
              active = true;
              definition = pkgs.writeText "kvm-networks.xml" (import ./libvirtd/networks/default.xml.nix);
            }
          ];

          pools = [
            {
              definition = ./libvirtd/pools/default.xml;

              # volumes = [
              # ];
            }
          ];
        };
      };
    };
  };
}
