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
      enableIPv6 = true;
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
      dua
      fd
      htop
      iotop
      privoxy
      qbittorrent
      qbittorrent-cli
      radarr
      sonarr
      wireguard-tools
      yazi
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
        primary-vpn = {
          configFile = config.sops.secrets.primary-vpn.path;
        };
      };
    };

    # wireguard = {
    #   interfaces = {
    #     wg0 = {
    #       privateKeyFile = "/persistence/etc/wireguard/wg0-private-key.conf";
    #
    #       ips = [
    #         "10.102.192.77/32"
    #       ];
    #
    #       peers = [
    #         {
    #           endpoint = "62.210.188.244:255";
    #           persistentKeepalive = 25;
    #           publicKey = "J68iV1X8gaCz+0gkNFm1Bv6uy6VNYhuMA/V7OOD0IlI=";
    #           presharedKeyFile = "/persistence/etc/wireguard/wg0-pre-shared-key-file.conf";
    #
    #           allowedIPs = [
    #             "0.0.0.0/0"
    #           ];
    #         }
    #       ];
    #
    #       # Ensure VPN endpoint is reachable via physical interface before tunnel comes up
    #       postSetup = ''
    #         # Retry route addition to handle network timing issues
    #         for i in {1..5}; do
    #           if ${pkgs.iproute2}/bin/ip route add 62.210.188.244/32 via 192.168.1.1 dev enp1s0 2>/dev/null; then
    #             break
    #           fi
    #           sleep 1
    #         done
    #       '';
    #
    #       postShutdown = ''
    #         ${pkgs.iproute2}/bin/ip route del 62.210.188.244/32 via 192.168.1.1 dev enp1s0 || true
    #       '';
    #     };
    #   };
    # };
  };

  # Add route for VPN endpoint via physical interface BEFORE wg-quick starts
  systemd.services.wg-quick-primary-vpn = {
    serviceConfig = {
      ExecStartPre = "-${pkgs.iproute2}/bin/ip route add 62.169.136.223/32 via 192.168.1.1 dev enp1s0";
      ExecStopPost = "-${pkgs.iproute2}/bin/ip route del 62.169.136.223/32 via 192.168.1.1 dev enp1s0";
    };
  };

  # Create script to merge qbittorrent config with sops secret
  environment.etc."qbittorrent/config-merger.sh" = {
    user = "qbittorrent";
    group = "qbittorrent";
    mode = "0500";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      CONFIG_DIR="${config.services.qbittorrent.profileDir}/qBittorrent/config"
      CONFIG_FILE="$CONFIG_DIR/qBittorrent.conf"
      CONFIG_BACKUP="$CONFIG_DIR/qBittorrent.conf.backup"
      SECRET_FILE="${config.sops.secrets."qbittorrent/webui/password".path}"

      # Ensure config directory exists
      mkdir -p "$CONFIG_DIR"

      # If config exists as a regular file (from previous run), use it as the base
      # Otherwise, use the Nix-generated config
      if [ -f "$CONFIG_FILE" ] && [ ! -L "$CONFIG_FILE" ]; then
        # Existing config from previous run - back it up
        ${pkgs.coreutils}/bin/cp "$CONFIG_FILE" "$CONFIG_BACKUP"
        BASE_CONFIG="$CONFIG_BACKUP"
      elif [ -L "$CONFIG_FILE" ]; then
        # Symlink to Nix store - read the target
        BASE_CONFIG=$(${pkgs.coreutils}/bin/readlink "$CONFIG_FILE")
        rm -f "$CONFIG_FILE"
      else
        # No config exists - will create new one
        BASE_CONFIG=""
      fi

      # Start with base config or create empty file
      if [ -n "$BASE_CONFIG" ] && [ -f "$BASE_CONFIG" ]; then
        ${pkgs.coreutils}/bin/cat "$BASE_CONFIG" > "$CONFIG_FILE"
      else
        # Create minimal config
        echo "[Meta]" > "$CONFIG_FILE"
        echo "MigrationVersion=8" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
      fi

      # Inject/update the password in the [Preferences] section
      if [ -f "$SECRET_FILE" ]; then
        PASSWORD=$(${pkgs.coreutils}/bin/cat "$SECRET_FILE")

        # Remove any existing password line and inject new one
        ${pkgs.gawk}/bin/awk -v pwd="$PASSWORD" '
          BEGIN { prefs_found=0; username_found=0; password_injected=0 }

          # Track if we are in the [Preferences] section
          /^\[Preferences\]/ { prefs_found=1; in_prefs=1; print; next }
          /^\[/ { in_prefs=0 }

          # Skip existing password lines
          /^WebUI\\Password_PBKDF2=/ && in_prefs { next }

          # Insert password after username
          in_prefs && /^WebUI\\Username=/ {
            print
            print "WebUI\\Password_PBKDF2=" pwd
            password_injected=1
            next
          }

          # If we are leaving [Preferences] and password not yet injected, add it
          /^\[/ && in_prefs && !password_injected {
            print "WebUI\\Password_PBKDF2=" pwd
            password_injected=1
          }

          { print }

          END {
            # If no [Preferences] section exists, create it
            if (!prefs_found) {
              print ""
              print "[Preferences]"
              print "WebUI\\Password_PBKDF2=" pwd
            }
          }
        ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"

        ${pkgs.coreutils}/bin/mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
      fi

      # Set proper permissions
      ${pkgs.coreutils}/bin/chmod 0640 "$CONFIG_FILE"
      ${pkgs.coreutils}/bin/chown qbittorrent:qbittorrent "$CONFIG_FILE"

      # Clean up backup
      rm -f "$CONFIG_BACKUP"
    '';
  };

  # Override qbittorrent service to inject secrets
  systemd.services.qbittorrent = {
    serviceConfig = {
      ExecStartPre = "+${pkgs.bash}/bin/bash /etc/qbittorrent/config-merger.sh";
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

  # Ensure mount points exist
  systemd.tmpfiles.rules = [
    "d /media/downloads 0755 root root -"
    "d /media/movies 0755 root root -"
    "d /media/tv 0755 root root -"
  ];

  # Configure CIFS mounts with automount
  systemd.mounts = [
    {
      what = "//192.168.1.97/downloads";
      where = "/media/downloads";
      type = "cifs";
      options = "credentials=${config.sops.secrets."samba/downloads-credentials".path},uid=qbittorrent,gid=qbittorrent,file_mode=0664,dir_mode=0775";
      wantedBy = [ ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
    }
    {
      what = "//192.168.1.97/movies";
      where = "/media/movies";
      type = "cifs";
      options = "credentials=${config.sops.secrets."samba/movies-credentials".path},uid=radarr,gid=radarr,file_mode=0664,dir_mode=0775";
      wantedBy = [ ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
    }
    {
      what = "//192.168.1.97/tv";
      where = "/media/tv";
      type = "cifs";
      options = "credentials=${config.sops.secrets."samba/tv-credentials".path},uid=sonarr,gid=sonarr,file_mode=0664,dir_mode=0775";
      wantedBy = [ ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
    }
  ];

  systemd.automounts = [
    {
      where = "/media/downloads";
      wantedBy = [ "multi-user.target" ];
    }
    {
      where = "/media/movies";
      wantedBy = [ "multi-user.target" ];
    }
    {
      where = "/media/tv";
      wantedBy = [ "multi-user.target" ];
    }
  ];

  services = {
    logrotate.checkConfig = false;

    bazarr = {
      enable = true;
      openFirewall = true;
    };

    flaresolverr = {
      enable = true;
      package = pkgs.unstable.flaresolverr;
      openFirewall = true;
    };

    jellyseerr = {
      enable = false;
    };

    overseerr = {
      enable = true;
      openFirewall = true;
    };

    radarr = {
      enable = true;
      openFirewall = true;
    };

    sonarr = {
      enable = true;
      openFirewall = true;
    };

    prowlarr = {
      enable = true;
      openFirewall = true;
    };

    qbittorrent = {
      enable = true;
      openFirewall = true;
      # package = pkgs.unstable.qbittorrent;
      torrentingPort = 15234;

      serverConfig = {
        Application = {
          "FileLogger\\Age" = 1;
          "FileLogger\\AgeType" = 1;
          "FileLogger\\Backup" = true;
          "FileLogger\\DeleteOld" = true;
          "FileLogger\\Enabled" = true;
          "FileLogger\\MaxSizeBytes" = 66560;
          "FileLogger\\Path" = "/var/lib/qBittorrent/qBittorrent/data/logs";
        };

        BitTorrent = {
          MergeTrackersEnabled = true;
          "Session\\AddExtensionToIncompleteFiles" = true;
          "Session\\AddTorrentToTopOfQueue" = true;
          "Session\\AnonymousModeEnabled" = true;
          "Session\\DefaultSavePath" = "/media/downloads/complete";
          "Session\\DisableAutoTMMByDefault" = false;
          "Session\\DisableAutoTMMTriggers\\CategorySavePathChanged" = false;
          "Session\\DisableAutoTMMTriggers\\DefaultSavePathChanged" = false;
          "Session\\ExcludedFileNames" = "";
          "Session\\GlobalMaxRatio" = 2;
          "Session\\IgnoreSlowTorrentsForQueueing" = true;
          "Session\\IncludeOverheadInLimits" = true;
          "Session\\Interface" = "primary-vpn";
          "Session\\InterfaceName" = "primary-vpn";
          "Session\\MaxActiveCheckingTorrents" = 2;
          "Session\\MaxActiveDownloads" = 20;
          "Session\\MaxActiveTorrents" = 20;
          "Session\\MaxActiveUploads" = 10;
          "Session\\Port" = 15234;
          "Session\\Preallocation" = true;
          "Session\\QueueingSystemEnabled" = true;
          "Session\\SSL\\Port" = 51603;
          "Session\\SlowTorrentsDownloadRate" = 100;
          "Session\\SlowTorrentsUploadRate" = 5;
          "Session\\SubcategoriesEnabled" = true;
          "Session\\Tags" = "arch, linux, nixos";
          "Session\\TempPath" = "/media/downloads/downloading";
          "Session\\TempPathEnabled" = true;
          "Session\\UseCategoryPathsInManualMode" = true;
          "Session\\UseUnwantedFolder" = true;
        };

        Core = {
          AutoDeleteAddedTorrentFile = "Never";
        };

        LegalNotice = {
          Accepted = true;
        };

        Meta = {
          MigrationVersion = 8;
        };

        Preferences = {
          "Advanced\\RecheckOnCompletion" = true;
          "General\\Locale" = "en";
          "MailNotification\\req_auth" = true;
          "WebUI\\AuthSubnetWhitelist" = "@Invalid()";
          "WebUI\\Port" = 8080;
          "WebUI\\Username" = "admin";
        };

        RSS = {
          "AutoDownloader\\DownloadRepacks" = true;
          "AutoDownloader\\SmartEpisodeFilter" = "s(\\d+)e(\\d+), (\\d+)x(\\d+), \"(\\d{4}[.\\-]\\d{1,2}[.\\-]\\d{1,2})\", \"(\\d{1,2}[.\\-]\\d{1,2}[.\\-]\\d{4})\"";
        };
      };
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
      vpnInterface = "primary-vpn";

      lanSubnets = [
        "192.168.1.0/24"
      ];

      lanInterfaces = [
        "enp1s0"
        "tailscale0"
      ];

      vpnEndpoints = [
        "62.210.188.244:51820"
        "62.169.136.223:51820"
      ];

      allowedServices = [
        {
          port = 6767;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
          ];
        }
        {
          port = 8080;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
          ];
        }
        {
          port = 5055;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
          ];
        }
        {
          port = 7878;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
          ];
        }
        {
          port = 8989;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
          ];
        }
        {
          port = 9696;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
          ];
        }
      ];

      vpnIncomingPorts = {
        tcp = [ "15000-20000" ];
        udp = [ "15000-20000" ];
      };

      exceptions = {
        dnsServers = [
          "149.112.112.112"
          "192.168.1.1"
          "9.9.9.9"
        ];

        domains = {
          nix = [
            "cache.nixos.org"
            "channels.nixos.org"
          ];
        };
      };
    };
  };

  sops = {
    defaultSopsFile = ../../secrets/main.enc.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/persistence/etc/ssh/keys/ssh_host_ed25519_key" ];
    secrets = {
      # "myservice/my_subdir/my_secret" = {
      #   mode = "0400";
      #   owner = config.users.users.nobody.name;
      #   group = config.users.users.nobody.group;
      #   restartUnits = ["example.service"];
      #   path = "/a/secret/path.yaml";
      #   format = "yaml"; # can be yaml, json, ini, dotenv, binary
      # };

      "primary-vpn" = {
        # restartUnits = ["example.service"];
        format = "yaml";
        group = config.users.users.root.group;
        mode = "0400";
        owner = config.users.users.root.name;
        path = "/etc/wireguard/primary-vpn.conf";
        sopsFile = ./secrets/vpn.yaml;
      };

      "qbittorrent/webui/password" = {
        format = "yaml";
        group = config.users.users.qbittorrent.group;
        mode = "0400";
        owner = config.users.users.qbittorrent.name;
        restartUnits = ["qbittorrent.service"];
        sopsFile = ./secrets/qbittorrent.yaml;
      };

      "samba/downloads-credentials" = {
        format = "yaml";
        group = config.users.users.root.group;
        mode = "0400";
        owner = config.users.users.root.name;
        sopsFile = ./secrets/samba.yaml;
      };

      "samba/tv-credentials" = {
        format = "yaml";
        group = config.users.users.root.group;
        mode = "0400";
        owner = config.users.users.root.name;
        sopsFile = ./secrets/samba.yaml;
      };

      "samba/movies-credentials" = {
        format = "yaml";
        group = config.users.users.root.group;
        mode = "0400";
        owner = config.users.users.root.name;
        sopsFile = ./secrets/samba.yaml;
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
