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
      enablePlymouth = false;
      inherit inputs lib outputs pkgs;
    })
    (import ../../modules/servers {
      # Nginx metrics
      enablePrometheusNginxExporter = true;
      # WireGuard VPN metrics
      enablePrometheusWireguardExporter = true;
      # Exportarr - media management metrics
      enablePrometheusExportarrRadarr = true;
      exportarrRadarrUrl = "http://localhost:7878";
      exportarrRadarrApiKeyFile = config.sops.secrets."exportarr/radarr-api-key".path;
      enablePrometheusExportarrSonarr = true;
      exportarrSonarrUrl = "http://localhost:8989";
      exportarrSonarrApiKeyFile = config.sops.secrets."exportarr/sonarr-api-key".path;
      enablePrometheusExportarrBazarr = true;
      exportarrBazarrUrl = "http://localhost:6767";
      exportarrBazarrApiKeyFile = config.sops.secrets."exportarr/bazarr-api-key".path;
      enablePrometheusExportarrProwlarr = true;
      exportarrProwlarrUrl = "http://localhost:9696";
      exportarrProwlarrApiKeyFile = config.sops.secrets."exportarr/prowlarr-api-key".path;
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
    # Enable NFS client support
    supportedFilesystems = [ "nfs" "nfs4" ];
  };

  environment = {
    pathsToLink = [ "/share/zsh" ];

    systemPackages = with pkgs; [
      cifs-utils
      dua
      fd
      htop
      iotop
      jq
      libnatpmp  # For ProtonVPN port forwarding
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

    persistence = {
      "/persistence" = {
        directories = [
          {
            directory = "/var/lib/qBittorrent";
            user = "root";
            group = "root";
            mode = "0755";
          }
          {
            directory = "/var/lib/radarr";
            user = "root";
            group = "root";
            mode = "0755";
          }
          {
            directory = "/var/lib/sonarr";
            user = "root";
            group = "root";
            mode = "0755";
          }
          {
            directory = "/var/lib/private/jellyseerr";
            user = "root";
            group = "root";
            mode = "0755";
          }
          {
            directory = "/var/lib/private/prowlarr";
            user = "root";
            group = "root";
            mode = "0755";
          }
          {
            directory = "/var/lib/bazarr";
            user = "root";
            group = "root";
            mode = "0755";
          }
          {
            directory = "/var/lib/deluge";
            user = "root";
            group = "root";
            mode = "0755";
          }
          {
            directory = "/var/lib/nginx-certs";
            user = "nginx";
            group = "nginx";
            mode = "0755";
          }
        ];
      };
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
        80
        443
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

  # WireGuard VPN watchdog script - restarts VPN if handshake is stale
  environment.etc."wireguard-watchdog.sh" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      INTERFACE="primary-vpn"
      # Maximum age in seconds before considering the tunnel stale (5 minutes)
      MAX_HANDSHAKE_AGE=300

      # Check if the interface exists
      if ! ${pkgs.wireguard-tools}/bin/wg show "$INTERFACE" 2>/dev/null | grep -q "interface"; then
        echo "[$(date)] Interface $INTERFACE does not exist, restarting..."
        systemctl restart "wg-quick-$INTERFACE"
        exit 0
      fi

      # Get the latest handshake timestamp (epoch seconds)
      HANDSHAKE_TIME=$(${pkgs.wireguard-tools}/bin/wg show "$INTERFACE" latest-handshakes | ${pkgs.gawk}/bin/awk '{print $2}')

      if [ -z "$HANDSHAKE_TIME" ] || [ "$HANDSHAKE_TIME" = "0" ]; then
        echo "[$(date)] No handshake recorded for $INTERFACE, restarting..."
        systemctl restart "wg-quick-$INTERFACE"
        exit 0
      fi

      CURRENT_TIME=$(date +%s)
      HANDSHAKE_AGE=$((CURRENT_TIME - HANDSHAKE_TIME))

      if [ "$HANDSHAKE_AGE" -gt "$MAX_HANDSHAKE_AGE" ]; then
        echo "[$(date)] Handshake for $INTERFACE is $HANDSHAKE_AGE seconds old (max: $MAX_HANDSHAKE_AGE), restarting..."
        systemctl restart "wg-quick-$INTERFACE"
      else
        echo "[$(date)] Handshake for $INTERFACE is $HANDSHAKE_AGE seconds old, tunnel is healthy"
      fi
    '';
  };

  # WireGuard watchdog service
  systemd.services.wireguard-watchdog = {
    description = "WireGuard VPN Watchdog";
    after = [ "network-online.target" "wg-quick-primary-vpn.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/wireguard-watchdog.sh";
    };
  };

  # Timer to run watchdog every 2 minutes
  systemd.timers.wireguard-watchdog = {
    description = "WireGuard VPN Watchdog Timer";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
      Unit = "wireguard-watchdog.service";
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

  # ProtonVPN port forwarding script (auto-detects qBittorrent or Deluge)
  environment.etc."protonvpn-portforward.sh" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      VPN_GATEWAY="10.2.0.1"
      PORT_FILE="/var/lib/protonvpn-port"
      QBITTORRENT_CONFIG="/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf"
      DELUGE_CONFIG="/var/lib/deluge/.config/deluge/core.conf"

      # Request port forwarding via NAT-PMP
      echo "[$(date)] Requesting port forward from ProtonVPN..."

      # Request TCP port
      OUTPUT_TCP=$(${pkgs.libnatpmp}/bin/natpmpc -g "$VPN_GATEWAY" -a 1 0 tcp 60 2>&1 || true)
      # Request UDP port (ProtonVPN typically assigns the same port for both)
      OUTPUT_UDP=$(${pkgs.libnatpmp}/bin/natpmpc -g "$VPN_GATEWAY" -a 1 0 udp 60 2>&1 || true)

      if echo "$OUTPUT_TCP" | grep -q "Mapped public port"; then
        FORWARDED_PORT=$(echo "$OUTPUT_TCP" | grep "Mapped public port" | grep -oP '\d+' | head -1)

        if [ -n "$FORWARDED_PORT" ] && [ "$FORWARDED_PORT" -gt 0 ]; then
          echo "[$(date)] Successfully got forwarded port: $FORWARDED_PORT"

          # Update Firewall Rules
          # ---------------------
          OLD_PORT="0"
          if [ -f "$PORT_FILE" ]; then
            OLD_PORT=$(cat "$PORT_FILE")
          fi

          if [ "$OLD_PORT" != "$FORWARDED_PORT" ]; then
            echo "[$(date)] Port changed from $OLD_PORT to $FORWARDED_PORT. Updating firewall (nftables)..."

            # Remove old rules (loop to handle duplicates)
            if [ "$OLD_PORT" != "0" ] && [ "$OLD_PORT" != "" ]; then
              while ${pkgs.nftables}/bin/nft delete rule inet filter input tcp dport "$OLD_PORT" accept 2>/dev/null; do :; done
              while ${pkgs.nftables}/bin/nft delete rule inet filter input udp dport "$OLD_PORT" accept 2>/dev/null; do :; done
            fi

            # Remove existing rules for the NEW port (to avoid duplicates if script runs again)
            while ${pkgs.nftables}/bin/nft delete rule inet filter input tcp dport "$FORWARDED_PORT" accept 2>/dev/null; do :; done
            while ${pkgs.nftables}/bin/nft delete rule inet filter input udp dport "$FORWARDED_PORT" accept 2>/dev/null; do :; done

            # Insert new rules at the TOP of the chain
            ${pkgs.nftables}/bin/nft insert rule inet filter input tcp dport "$FORWARDED_PORT" accept
            ${pkgs.nftables}/bin/nft insert rule inet filter input udp dport "$FORWARDED_PORT" accept
          else
             # Ensure rules exist (check if ANY rule exists, if not insert)
             if ! ${pkgs.nftables}/bin/nft list ruleset | grep -q "tcp dport $FORWARDED_PORT accept"; then
                 ${pkgs.nftables}/bin/nft insert rule inet filter input tcp dport "$FORWARDED_PORT" accept
             fi
             if ! ${pkgs.nftables}/bin/nft list ruleset | grep -q "udp dport $FORWARDED_PORT" | grep -q "accept"; then
                 ${pkgs.nftables}/bin/nft insert rule inet filter input udp dport "$FORWARDED_PORT" accept
             fi
          fi

          echo "$FORWARDED_PORT" > "$PORT_FILE"
          chmod 644 "$PORT_FILE"

          # Auto-detect which torrent client is running and update it
          if systemctl is-active --quiet qbittorrent; then
            echo "[$(date)] qBittorrent is active, updating port..."
            if [ -f "$QBITTORRENT_CONFIG" ]; then
              CURRENT_PORT=$(grep "Session\\\\Port=" "$QBITTORRENT_CONFIG" | cut -d= -f2 || echo "0")

              if [ "$CURRENT_PORT" != "$FORWARDED_PORT" ]; then
                echo "[$(date)] Updating qBittorrent port from $CURRENT_PORT to $FORWARDED_PORT"
                sed -i "s/^Session\\\\Port=.*/Session\\\\Port=$FORWARDED_PORT/" "$QBITTORRENT_CONFIG"
                systemctl start qbittorrent # This restarts the service as it's already running
              else
                echo "[$(date)] qBittorrent already using correct port $FORWARDED_PORT"
              fi
            fi
          elif systemctl is-active --quiet deluged; then
            echo "[$(date)] Deluge is active, updating port..."
            if [ -f "$DELUGE_CONFIG" ]; then
              # Update Deluge's core.conf using jq to modify the JSON
              ${pkgs.jq}/bin/jq ".listen_ports = [$FORWARDED_PORT, $FORWARDED_PORT]" "$DELUGE_CONFIG" > "$DELUGE_CONFIG.tmp"
              mv "$DELUGE_CONFIG.tmp" "$DELUGE_CONFIG"
              chown deluge:deluge "$DELUGE_CONFIG"
              chmod 600 "$DELUGE_CONFIG"
              systemctl restart deluged
              echo "[$(date)] Updated Deluge port to $FORWARDED_PORT and restarted service"
            fi
          else
            echo "[$(date)] No active torrent client found (qBittorrent or Deluge)"
          fi
        else
          echo "[$(date)] ERROR: Failed to parse forwarded port from output"
          exit 1
        fi
      else
        echo "[$(date)] ERROR: Port forwarding request failed"
        echo "$OUTPUT_TCP"
        exit 1
      fi
    '';
  };

  # Override qbittorrent service to inject secrets and configure aggressive restarts
  systemd.services.qbittorrent = {
    # Restart qBittorrent if NFS mounts are remounted (prevents stale file handles)
    bindsTo = [ "media-downloads.mount" ];
    after = [ "media-downloads.mount" "media-movies.mount" "media-tv.mount" ];

    serviceConfig = {
      ExecStart = lib.mkForce "${config.services.qbittorrent.package}/bin/qbittorrent-nox --profile=/var/lib/qBittorrent/ --webui-port=8080";
      ExecStartPre = "+${pkgs.bash}/bin/bash /etc/qbittorrent/config-merger.sh";
      Restart = "always";
      RestartSec = "5s";
      StartLimitBurst = 0; # Unlimited restart attempts

      # Set umask to 002 so files are created with group write permissions (664)
      # and directories with 775. This allows radarr/sonarr to modify files.
      UMask = "0002";

      # Ensure qbittorrent runs with supplementary groups (including media group)
      SupplementaryGroups = [ "media" ];
    };
  };

  # ProtonVPN port forwarding service
  systemd.services.protonvpn-portforward = {
    description = "ProtonVPN Port Forwarding";
    after = [ "network-online.target" "wg-quick-primary-vpn.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/protonvpn-portforward.sh";
      RemainAfterExit = false;
    };
  };

  # Timer to refresh port forwarding every 45 seconds (expires after 60s)
  systemd.timers.protonvpn-portforward = {
    description = "ProtonVPN Port Forwarding Refresh Timer";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "10s";       # Start 10 seconds after boot
      OnUnitActiveSec = "45s"; # Refresh every 45 seconds
      Unit = "protonvpn-portforward.service";
    };
  };

  # Configure umask for all media services to create files with group write permissions
  systemd.services.radarr = {
    serviceConfig = {
      UMask = "0002";
      SupplementaryGroups = [ "media" ];
    };
    preStart = ''
      CONFIG_FILE="/var/lib/radarr/config.xml"
      if [ -f "$CONFIG_FILE" ]; then
        if ! grep -q "<UrlBase>/radarr</UrlBase>" "$CONFIG_FILE"; then
          ${pkgs.gnused}/bin/sed -i 's|<UrlBase></UrlBase>|<UrlBase>/radarr</UrlBase>|g' "$CONFIG_FILE"
          ${pkgs.gnused}/bin/sed -i '/<Config>/a\  <UrlBase>/radarr</UrlBase>' "$CONFIG_FILE" 2>/dev/null || true
        fi
      fi
    '';
  };

  systemd.services.sonarr = {
    serviceConfig = {
      UMask = "0002";
      SupplementaryGroups = [ "media" ];
    };
    preStart = ''
      CONFIG_FILE="/var/lib/sonarr/config.xml"
      if [ -f "$CONFIG_FILE" ]; then
        if ! grep -q "<UrlBase>/sonarr</UrlBase>" "$CONFIG_FILE"; then
          ${pkgs.gnused}/bin/sed -i 's|<UrlBase></UrlBase>|<UrlBase>/sonarr</UrlBase>|g' "$CONFIG_FILE"
          ${pkgs.gnused}/bin/sed -i '/<Config>/a\  <UrlBase>/sonarr</UrlBase>' "$CONFIG_FILE" 2>/dev/null || true
        fi
      fi
    '';
  };

  systemd.services.bazarr = {
    serviceConfig = {
      UMask = "0002";
      SupplementaryGroups = [ "media" "tv" "movies" ];
    };
    preStart = ''
      CONFIG_FILE="/var/lib/bazarr/config/config.ini"
      if [ -f "$CONFIG_FILE" ]; then
        if ! grep -q "^base_url = /bazarr" "$CONFIG_FILE"; then
          ${pkgs.gnused}/bin/sed -i 's|^base_url =.*|base_url = /bazarr|g' "$CONFIG_FILE"
        fi
      fi
    '';
  };

  systemd.services.prowlarr = {
    serviceConfig = {
      UMask = "0002";
      SupplementaryGroups = [ "media" ];
    };
    preStart = ''
      CONFIG_FILE="/var/lib/private/prowlarr/config.xml"
      if [ -f "$CONFIG_FILE" ]; then
        if ! grep -q "<UrlBase>/prowlarr</UrlBase>" "$CONFIG_FILE"; then
          ${pkgs.gnused}/bin/sed -i 's|<UrlBase></UrlBase>|<UrlBase>/prowlarr</UrlBase>|g' "$CONFIG_FILE"
          ${pkgs.gnused}/bin/sed -i '/<Config>/a\  <UrlBase>/prowlarr</UrlBase>' "$CONFIG_FILE" 2>/dev/null || true
        fi
      fi
    '';
  };

  systemd.services.jellyseerr = {
    serviceConfig = {
      UMask = "0002";
      SupplementaryGroups = [ "media" "tv" "movies" ];
    };
  };

  # Deluge configuration initialization script
  environment.etc."deluge/init-config.sh" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      CONFIG_DIR="/var/lib/deluge/.config/deluge"
      CORE_CONF="$CONFIG_DIR/core.conf"
      WEB_CONF="$CONFIG_DIR/web.conf"
      AUTH_FILE="$CONFIG_DIR/auth"

      # Ensure config directory exists
      mkdir -p "$CONFIG_DIR"
      chown -R deluge:deluge "$CONFIG_DIR"

      # Initialize core.conf if it doesn't exist
      if [ ! -f "$CORE_CONF" ]; then
        cat > "$CORE_CONF" <<'EOF'
{
  "file": 1,
  "format": 1,
  "download_location": "/media/downloads/complete",
  "move_completed": true,
  "move_completed_path": "/media/downloads/complete",
  "torrentfiles_location": "/media/downloads/downloading",
  "copy_torrent_file": true,
  "listen_interface": "primary-vpn",
  "outgoing_interface": "primary-vpn",
  "listen_ports": [15234, 15234],
  "random_port": false,
  "max_connections_global": 500,
  "max_connections_per_torrent": 100,
  "max_upload_slots_global": 50,
  "max_upload_slots_per_torrent": 4,
  "max_active_downloading": 10,
  "max_active_seeding": 20,
  "max_active_limit": 20,
  "dont_count_slow_torrents": true,
  "queue_new_to_top": true,
  "stop_seed_at_ratio": true,
  "stop_seed_ratio": 2.0,
  "remove_seed_at_ratio": false,
  "cache_size": 512,
  "cache_expiry": 300,
  "dht": true,
  "upnp": false,
  "natpmp": false,
  "utpex": true,
  "lsd": false,
  "enc_prefer_rc4": true,
  "enc_level": 1,
  "enc_in_policy": 1,
  "enc_out_policy": 1,
  "max_download_speed": -1.0,
  "max_upload_speed": -1.0,
  "max_half_open_connections": 50,
  "max_connections_per_second": 20,
  "prioritize_first_last_pieces": true,
  "sequential_download": false,
  "pre_allocate_storage": false,
  "add_paused": false,
  "auto_managed": true,
  "compact_allocation": false,
  "enabled_plugins": [],
  "allow_remote": true,
  "daemon_port": 58846
}
EOF
        chown deluge:deluge "$CORE_CONF"
        chmod 600 "$CORE_CONF"
        echo "Created initial core.conf"
      fi

      # Initialize web.conf if it doesn't exist
      if [ ! -f "$WEB_CONF" ]; then
        cat > "$WEB_CONF" <<'EOF'
{
  "file": 1,
  "format": 1,
  "port": 8112,
  "enabled_plugins": [],
  "pwd_salt": "deluge",
  "pwd_sha1": "67b183a3025b68ac0f8edf8f3157f67b7814721e",
  "session_timeout": 3600,
  "sessions": {},
  "sidebar_show_zero": false,
  "sidebar_multiple_filters": true,
  "show_session_speed": true,
  "show_sidebar": true,
  "theme": "gray",
  "default_daemon": "127.0.0.1:58846",
  "https": false,
  "interface": "0.0.0.0",
  "base": "/",
  "first_login": true
}
EOF
        chown deluge:deluge "$WEB_CONF"
        chmod 600 "$WEB_CONF"
        echo "Created initial web.conf"
      fi

      # Initialize auth file if it doesn't exist (username: admin, password: deluge)
      if [ ! -f "$AUTH_FILE" ]; then
        echo "admin:deluge:10" > "$AUTH_FILE"
        chown deluge:deluge "$AUTH_FILE"
        chmod 600 "$AUTH_FILE"
        echo "Created initial auth file"
      fi

      # Initialize hostlist.conf if it doesn't exist
      HOSTLIST_CONF="$CONFIG_DIR/hostlist.conf"
      if [ ! -f "$HOSTLIST_CONF" ]; then
        cat > "$HOSTLIST_CONF" <<'EOF'
{
  "file": 1,
  "format": 1,
  "hosts": [
    [
      "localclient",
      "127.0.0.1",
      58846,
      "admin",
      "deluge"
    ]
  ]
}
EOF
        chown deluge:deluge "$HOSTLIST_CONF"
        chmod 600 "$HOSTLIST_CONF"
        echo "Created initial hostlist.conf"
      fi
    '';
  };

  # Configure Deluge services
  systemd.services.deluged.serviceConfig = {
    ExecStartPre = "+${pkgs.bash}/bin/bash /etc/deluge/init-config.sh";
    UMask = "0002";
    SupplementaryGroups = [ "media" ];
  };

  systemd.services.delugeweb.serviceConfig = {
    UMask = "0002";
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

  # Configure NFS mounts with automount (optimized for torrenting performance)
  # Storage server (192.168.1.97) exports from /media/storage/* paths
  systemd.mounts = [
    {
      what = "192.168.1.97:/media/storage/downloads";
      where = "/media/downloads";
      type = "nfs";
      # Performance-optimized NFS options for qBittorrent:
      # - rsize/wsize=1MB for maximum throughput
      # - async on downloads (faster writes, safe since qBittorrent verifies data)
      # - noatime/nodiratime (no access time updates = less metadata writes)
      # - actimeo=30 (cache attributes for 30 sec = faster stale handle detection)
      # - lookupcache=all (aggressive file lookup caching)
      # - hard,intr (reliable, but interruptible on hung operations)
      options = "rw,hard,intr,tcp,nfsvers=4.2,rsize=1048576,wsize=1048576,timeo=600,retrans=2,noatime,nodiratime,async,lookupcache=all,actimeo=30";
      wantedBy = [ ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
    }
    {
      what = "192.168.1.97:/media/storage/media/Movies";
      where = "/media/movies";
      type = "nfs";
      # No async for movies/tv (Radarr/Sonarr move completed files here)
      # actimeo=30 for faster stale handle detection after server reboots
      options = "rw,hard,intr,tcp,nfsvers=4.2,rsize=1048576,wsize=1048576,timeo=600,retrans=2,noatime,nodiratime,lookupcache=all,actimeo=30";
      wantedBy = [ ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
    }
    {
      what = "192.168.1.97:/media/storage/media/TV";
      where = "/media/tv";
      type = "nfs";
      # No async for movies/tv (Radarr/Sonarr move completed files here)
      # actimeo=30 for faster stale handle detection after server reboots
      options = "rw,hard,intr,tcp,nfsvers=4.2,rsize=1048576,wsize=1048576,timeo=600,retrans=2,noatime,nodiratime,lookupcache=all,actimeo=30";
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

  # Generate self-signed certificate for nginx
  systemd.services.nginx-self-signed-cert = {
    description = "Generate self-signed certificate for nginx";
    wantedBy = [ "multi-user.target" ];
    before = [ "nginx.service" ];
    script = ''
      CERT_DIR="/var/lib/nginx-certs"
      mkdir -p "$CERT_DIR"

      if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 \
          -keyout "$CERT_DIR/key.pem" \
          -out "$CERT_DIR/cert.pem" \
          -days 3650 -nodes \
          -subj "/CN=download-server-1.lan"
        chown nginx:nginx "$CERT_DIR/key.pem"
        chown nginx:nginx "$CERT_DIR/cert.pem"
        chmod 600 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  services = {
    logrotate.checkConfig = false;

    # NFS client support - required for NFS mounts to work
    rpcbind.enable = true;  # Required for NFS

    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."download-server-1.lan" = {
        forceSSL = true;
        sslCertificate = "/var/lib/nginx-certs/cert.pem";
        sslCertificateKey = "/var/lib/nginx-certs/key.pem";

        locations = {
          "/qbittorrent/" = {
            proxyPass = "http://127.0.0.1:8080/";
            extraConfig = ''
              proxy_set_header Host 127.0.0.1:8080;
              proxy_set_header X-Forwarded-Host $http_host;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Referer "";
              proxy_cookie_path / /qbittorrent;
              proxy_redirect / /qbittorrent/;
              proxy_set_header X-Frame-Options SAMEORIGIN;
            '';
          };

          "/radarr/" = {
            proxyPass = "http://127.0.0.1:7878/radarr/";
            extraConfig = ''
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };

          "/sonarr/" = {
            proxyPass = "http://127.0.0.1:8989/sonarr/";
            extraConfig = ''
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };

          "/bazarr/" = {
            proxyPass = "http://127.0.0.1:6767/bazarr/";
            extraConfig = ''
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };

          "/prowlarr/" = {
            proxyPass = "http://127.0.0.1:9696/prowlarr/";
            extraConfig = ''
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };

          "/jellyseerr" = {
            proxyPass = "http://127.0.0.1:5055";
            extraConfig = ''
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_redirect ~^/(.*)$ /jellyseerr/$1;
              rewrite ^/jellyseerr(/.*)$ $1 break;
              rewrite ^/jellyseerr$ / break;
            '';
          };

          # Jellyseerr static assets and API (Next.js at root paths)
          "~ ^/(api/v1/|_next/|apple-touch-icon|favicon|logo)" = {
            proxyPass = "http://127.0.0.1:5055";
            extraConfig = ''
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };

          "/flaresolverr/" = {
            proxyPass = "http://127.0.0.1:8191/";
            extraConfig = ''
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };

          # Nginx stub_status for prometheus-nginx-exporter
          "/nginx_status" = {
            extraConfig = ''
              stub_status on;
              access_log off;
              allow 127.0.0.1;
              deny all;
            '';
          };
        };
      };
    };

    bazarr = {
      enable = true;
      openFirewall = true;
    };

    flaresolverr = {
      enable = true;
      package = pkgs.unstable.flaresolverr;
      openFirewall = true;
    };

    i2pd = {
      enable = true;

      proto = {
        sam = {
          enable = true;
        };
      };
    };

    jellyseerr = {
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
      package = pkgs.qbittorrent;  # Uses overlayed version with libtorrent 1.2.x
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
          "Session\\AnonymousModeEnabled" = false;  # Disabled - was causing stalled torrents
          "Session\\DefaultSavePath" = "/media/downloads/complete";
          "Session\\DisableAutoTMMByDefault" = false;
          "Session\\DisableAutoTMMTriggers\\CategorySavePathChanged" = false;
          "Session\\DisableAutoTMMTriggers\\DefaultSavePathChanged" = false;
          "Session\\ExcludedFileNames" = "";
          "Session\\GlobalMaxRatio" = 2;
          "Session\\I2P\\Enabled" = false;  # Temporarily disabled to debug crashes
          "Session\\I2P\\MixedMode" = true;
          "Session\\IgnoreSlowTorrentsForQueueing" = true;
          "Session\\IncludeOverheadInLimits" = true;
          "Session\\Interface" = "primary-vpn";
          "Session\\InterfaceName" = "primary-vpn";
          "Session\\MaxActiveCheckingTorrents" = 2;
          "Session\\MaxActiveDownloads" = 10;  # Increased from 5
          "Session\\MaxActiveTorrents" = 20;   # Increased from 10
          "Session\\MaxActiveUploads" = 20;    # Increased from 15
          "Session\\Port" = 15234;
          "Session\\Preallocation" = false;
          "Session\\QueueingSystemEnabled" = true;
          "Session\\SSL\\Port" = 51603;
          "Session\\SlowTorrentsDownloadRate" = 10;   # Lowered from 100 (KB/s) - less aggressive
          "Session\\SlowTorrentsUploadRate" = 1;    # Lowered from 5 (KB/s) - less aggressive
          "Session\\SubcategoriesEnabled" = true;
          "Session\\Tags" = "arch, linux, nixos";
          "Session\\TempPath" = "/media/downloads/downloading";
          "Session\\TempPathEnabled" = true;
          "Session\\UseCategoryPathsInManualMode" = true;
          "Session\\UseUnwantedFolder" = true;

          # Disk cache settings (optimized for NFS performance)
          "Session\\DiskCacheSize" = 512;                    # 512 MB cache (can increase with NFS)
          "Session\\DiskCacheTTL" = 300;                     # Keep in cache for 5 minutes
          "Session\\UseOSCache" = true;                      # Use OS cache with NFS (better performance)

          # File handling optimizations
          "Session\\FilePoolSize" = 500;                     # Keep more files open for better performance

          # Connection limits (prevent overwhelming the system)
          "Session\\MaxConnections" = 500;                   # Global connection limit
          "Session\\MaxConnectionsPerTorrent" = 100;         # Per-torrent connection limit
          "Session\\MaxUploads" = 50;                        # Global upload slots
          "Session\\MaxUploadsPerTorrent" = 4;               # Per-torrent upload slots

          # Performance settings
          "Session\\AnnounceToAllTiers" = true;              # Better peer discovery
          "Session\\AnnounceToAllTrackers" = true;           # Announce to all trackers
          "Session\\AsyncIOThreadsCount" = 8;                # More async I/O threads for network storage
          "Session\\SendBufferWatermark" = 5120;             # 5 MB send buffer
          "Session\\SendBufferLowWatermark" = 512;           # 512 KB low watermark
          "Session\\SocketBacklogSize" = 30;                 # Connection queue size

          # Protocol settings
          "Session\\uTPRateLimited" = true;                  # Rate limit uTP protocol
          "Session\\uTP_mix_mode" = 0;                       # Prefer TCP over uTP (better for VPN)
          "Session\\DHTEnabled" = true;                      # Enable DHT for peer discovery
          "Session\\PeXEnabled" = true;                      # Enable Peer Exchange
          "Session\\LSDEnabled" = false;                     # Disable LSD (doesn't work over VPN)

          # Reliability settings
          "Session\\SaveResumeDataInterval" = 5;             # Save resume data every 5 minutes
          "Session\\StopTrackerTimeout" = 2;                 # Don't wait long when stopping torrents

          # Encryption settings (for privacy)
          "Session\\Encryption" = 1;                         # Prefer encrypted connections

          # Additional connectivity settings to prevent stalls
          "Session\\OutgoingPortsMin" = 0;                   # Use random ports for outgoing connections
          "Session\\OutgoingPortsMax" = 0;                   # Use random ports for outgoing connections
          "Session\\RefreshInterval" = 1500;                 # Refresh interval in ms (default)
          "Session\\ResumeDataStorageType" = "SQLite";       # Use SQLite for better reliability
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
          "Advanced\\RecheckOnCompletion" = false;           # Disabled to reduce I/O load on network shares
          "Advanced\\SaveResumeDataInterval" = 5;            # Save resume data every 5 minutes
          "Advanced\\RecheckAfterFileMove" = false;          # Don't recheck after moving files
          "Advanced\\MaxMemoryWorkingSetLimit" = 4096;       # Limit RAM usage to 4GB to prevent crashes
          "General\\Locale" = "en";
          "MailNotification\\req_auth" = true;
          "WebUI\\AuthSubnetWhitelist" = "@Invalid()";
          "WebUI\\Port" = 8080;
          "WebUI\\Username" = "admin";
          "WebUI\\HostHeaderValidation" = false;
          "WebUI\\CSRFProtection" = false;
        };

        RSS = {
          "AutoDownloader\\DownloadRepacks" = true;
          "AutoDownloader\\SmartEpisodeFilter" = "s(\\d+)e(\\d+), (\\d+)x(\\d+), \"(\\d{4}[.\\-]\\d{1,2}[.\\-]\\d{1,2})\", \"(\\d{1,2}[.\\-]\\d{1,2}[.\\-]\\d{4})\"";
        };
      };
    };

    deluge = {
      enable = false;
      openFirewall = true;
      web.enable = true;
      web.port = 8112;
      dataDir = "/var/lib/deluge";
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
          port = 443;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
            "192.168.1.66"
          ];
        }
        {
          port = 6767;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
            "192.168.1.66"
          ];
        }
        {
          port = 8080;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
            "192.168.1.66"
          ];
        }
        {
          port = 8112;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
            "192.168.1.66"
          ];
        }
        {
          port = 5055;
          sources = [
            "192.168.1.129"
            "192.168.1.187"
            "192.168.1.39"
            "192.168.1.66"
          ];
        }
        {
          port = 7878;
          sources = [
            "192.168.1.187"
            "192.168.1.66"
            "192.168.1.39"
          ];
        }
        {
          port = 8989;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
            "192.168.1.66"
          ];
        }
        {
          port = 9696;
          sources = [
            "192.168.1.187"
            "192.168.1.39"
            "192.168.1.66"
          ];
        }
      ];

      vpnIncomingPorts = {
        tcp = [ "10000-65535" ];
        udp = [ "10000-65535" ];
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

      # Exportarr API keys for Prometheus exporters
      "exportarr/radarr-api-key" = {
        format = "yaml";
        mode = "0400";
        sopsFile = ./secrets/exportarr.yaml;
      };
      "exportarr/sonarr-api-key" = {
        format = "yaml";
        mode = "0400";
        sopsFile = ./secrets/exportarr.yaml;
      };
      "exportarr/bazarr-api-key" = {
        format = "yaml";
        mode = "0400";
        sopsFile = ./secrets/exportarr.yaml;
      };
      "exportarr/prowlarr-api-key" = {
        format = "yaml";
        mode = "0400";
        sopsFile = ./secrets/exportarr.yaml;
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
    # Fixed GIDs to match home-storage-server-1
    groups = {
      media = { gid = 5000; };  # Shared group for all media services
      qbittorrent = { gid = lib.mkForce 5001; };
      radarr = { gid = lib.mkForce 5002; };
      sonarr = { gid = lib.mkForce 5003; };
      bazarr = { gid = lib.mkForce 5007; };
      prowlarr = { gid = lib.mkForce 5008; };
      jellyseerr = { gid = lib.mkForce 5009; };
      deluge = { gid = lib.mkForce 5010; };
      movies = { gid = 5011; };
      tv = { gid = 5013; };
    };

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

      # Override service users with fixed UIDs/GIDs to match storage server
      qbittorrent = {
        uid = lib.mkForce 5001;
        group = lib.mkForce "qbittorrent";
        extraGroups = [ "media" ];  # Add to shared media group
        isSystemUser = lib.mkForce true;
      };
      radarr = {
        uid = lib.mkForce 5002;
        group = lib.mkForce "radarr";
        extraGroups = [ "media" "movies" ];  # Add to shared media group
        isSystemUser = lib.mkForce true;
      };
      sonarr = {
        uid = lib.mkForce 5003;
        group = lib.mkForce "sonarr";
        extraGroups = [ "media" "tv" ];  # Add to shared media group
        isSystemUser = lib.mkForce true;
      };
      bazarr = {
        uid = lib.mkForce 5007;
        group = lib.mkForce "bazarr";
        extraGroups = [ "media" "movies" "tv" ];  # Add to shared media group
        isSystemUser = lib.mkForce true;
      };
      prowlarr = {
        uid = lib.mkForce 5008;
        group = lib.mkForce "prowlarr";
        extraGroups = [ "media" ];  # Add to shared media group
        isSystemUser = lib.mkForce true;
      };
      jellyseerr = {
        uid = lib.mkForce 5009;
        group = lib.mkForce "jellyseerr";
        extraGroups = [ "media" ];  # Add to shared media group
        isSystemUser = lib.mkForce true;
      };
      deluge = {
        uid = lib.mkForce 5010;
        group = lib.mkForce "deluge";
        extraGroups = [ "media" ];
        isSystemUser = lib.mkForce true;
      };
    };
  };
}
