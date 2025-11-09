{ config
, inputs
, lib
, outputs
, pkgs
, ...
}: {
  imports = [
    (import ../../modules/locale { })
    (import ../../modules/base {
      enableImpermanence = true;
      inherit inputs lib outputs pkgs;
    })
    ../../modules/amnezia-vpn-gateway
    ./disko-config.nix
    ./hardware-configuration.nix
  ];

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
    sudo-rs = {
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
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };
}
