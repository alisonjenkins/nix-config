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
    ../../modules/proxy-vpn-gateway
    # ../../app-profiles/server-base/luks-tor-unlock
    ../../app-profiles/storage-server
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
      cifs-utils
      privoxy
      qbittorrent
      qbittorrent-cli
      radarr
      sonarr
      wireguard-tools
    ];

    variables = {
      PATH = [
        "\${HOME}/.local/bin"
        "\${HOME}/.config/rofi/scripts"
      ];
    };
  };

  networking = {
    hostName = "download-server-1";
    networkmanager.enable = true;

    firewall = {
      enable = true;
      allowPing = true;

      allowedTCPPorts = [
        22
        8118
      ];
      allowedUDPPorts = [];

      # VPN leak protection - only allow Wireguard and internal network traffic
      # extraCommands = ''
      #   # Allow loopback
      #   iptables -A OUTPUT -o lo -j ACCEPT
      #
      #   # Allow internal network traffic (adjust ranges as needed)
      #   iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
      #   iptables -A OUTPUT -d 192.168.1.0/16 -j ACCEPT
      #   # iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
      #   # iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
      #
      #   # Allow Wireguard traffic (port 51820 is default, adjust if different)
      #   iptables -A OUTPUT -p udp --dport 51820 -j ACCEPT
      #
      #   # Allow traffic through VPN tunnel interfaces (common VPN interface names)
      #   iptables -A OUTPUT -o wg+ -j ACCEPT
      #   iptables -A OUTPUT -o tun+ -j ACCEPT
      #   iptables -A OUTPUT -o tap+ -j ACCEPT
      #
      #   # Allow DNS through VPN interfaces only
      #   iptables -A OUTPUT -o wg+ -p udp --dport 53 -j ACCEPT
      #   iptables -A OUTPUT -o tun+ -p udp --dport 53 -j ACCEPT
      #   iptables -A OUTPUT -o wg+ -p tcp --dport 53 -j ACCEPT
      #   iptables -A OUTPUT -o tun+ -p tcp --dport 53 -j ACCEPT
      #
      #   # Allow established and related connections
      #   iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      #
      #   # Block all other outbound traffic to internet
      #   iptables -A OUTPUT -j DROP
      # '';
      #
      # extraStopCommands = ''
      #   # Clean up custom rules when firewall stops
      #   iptables -D OUTPUT -o lo -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -d 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -d 192.168.1.0/16 -j ACCEPT 2>/dev/null || true
      #   # iptables -D OUTPUT -d 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      #   # iptables -D OUTPUT -d 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -o wg+ -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -o tun+ -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -o tap+ -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -o wg+ -p udp --dport 53 -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -o tun+ -p udp --dport 53 -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -o wg+ -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -o tun+ -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      #   iptables -D OUTPUT -j DROP 2>/dev/null || true
      # '';
    };

    wg-quick = {
      interfaces = {
        wg0 = {
          dns = [ "127.0.0.1" ];
          privateKeyFile = "/persistence/etc/wireguard/wg0-private-key.conf";

          address = [
            "10.102.192.77/32"
          ];

          peers = [
            {
              endpoint = "62.210.188.244:255";
              persistentKeepalive = 25;
              publicKey = "J68iV1X8gaCz+0gkNFm1Bv6uy6VNYhuMA/V7OOD0IlI=";
              presharedKeyFile = "/persistence/etc/wireguard/wg0-pre-shared-key-file.conf";

              allowedIPs = [
                "0.0.0.0/0"
              ];
            }
          ];
        };
      };
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

    bazarr = {
      enable = false;
      openFirewall = true;
    };

    jellyseerr = {
      enable = false;
    };

    radarr = {
      enable = false;
      openFirewall = true;
    };

    sonarr = {
      enable = false;
      openFirewall = true;
    };

    qbittorrent = {
      enable = true;
      openFirewall = true;
    };

    privoxy = {
      enable = false;
      enableTor = true;

      settings = {
        listen-address = "0.0.0.0:8118";
        forward-socks5 = ".onion localhost:9050 .";
      };
    };

    proxyVpnGateway = {
      enable = true;
      vpnInterface = "wg0";

      lanSubnets = [
        "192.168.1.0/24"
      ];

      lanInterfaces = [
        "enp1s0"
        "tailscale0"
      ];

      vpnEndpoints = [
        "62.210.188.244"
      ];

      exceptions = {
        dnsServers = [
          "149.112.112.112"
          "192.168.1.1"
          "9.9.9.9"
        ];
      };
    };
  };

  # sops = {
  #   defaultSopsFile = ../../secrets/main.enc.yaml;
  #   defaultSopsFormat = "yaml";
  #   age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  #   secrets = {
  #     # "myservice/my_subdir/my_secret" = {
  #     #   mode = "0400";
  #     #   owner = config.users.users.nobody.name;
  #     #   group = config.users.users.nobody.group;
  #     #   restartUnits = ["example.service"];
  #     #   path = "/a/secret/path.yaml";
  #     #   format = "yaml"; # can be yaml, json, ini, dotenv, binary
  # #     # };
  # #     # home_enc_key = {
  # #     #   format = "binary";
  # #     #   group = config.users.users.nobody.group;
  # #     #   mode = "0400";
  # #     #   neededForUsers = true;
  # #     #   owner = config.users.users.root.name;
  # #     #   path = "/etc/luks/home.key";
  # #     #   sopsFile = ../../secrets/ali-desktop/home-enc-key.enc.bin;
  # #     # };
  #   };
  # };

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
        # hashedPasswordFile = config.sops.secrets.ali.path;
        # hashedPasswordFile = "/persistence/passwords/ali";
        initialPassword = "initPw!";
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };
}
