{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.proxyVpnGateway;
in
{
  options.services.proxyVpnGateway = {
    enable = mkEnableOption "the single-interface SOCKS5 VPN proxy gateway";

    exceptions = {
      dnsServers = mkOption {
        type = types.listOf types.str;
        default = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4" ];
        description = "Public DNS servers to use for resolving exception domains outside the VPN.";
      };
      domains = {
        github = mkOption {
          type = types.listOf types.str;
          default = [ "github.com" "api.github.com" "codeload.github.com" ];
          description = "A list of domains related to GitHub.";
        };

        nix = mkOption {
          type = types.listOf types.str;
          default = [ "cache.nixos.org" ];
          description = "A list of domains related to Nix binary caches.";
        };
      };
    };

    lanInterfaces = mkOption {
      type = types.listOf types.str;
      description = "The network interfaces connected to LANs.";
      example = ["enp3s0"];
    };

    lanSubnets = mkOption {
      type = types.listOf types.str;
      description = "The IP subnets for your LANs.";
      example = ["192.168.1.0/24"];
    };

    proxy = {
      auth = mkOption {
        type = types.str;
        default = "none";
        description = "Authentication for the proxy. Use 'none' or 'user:pass'.";
      };

      port = mkOption {
        type = types.port;
        default = 1080;
        description = "The TCP port on which the SOCKS5 proxy will listen.";
      };
    };

    updateFrequency = mkOption {
      type = types.str;
      default = "1h";
      description = "How often to update the IP sets for exception domains. Uses systemd time format.";
    };

    vpnEndpoints = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of VPN endpoint hostnames or IP addresses that should be allowed through the firewall.
        Supports port specification in the format "host:port" for UDP traffic.
        Examples:
          - "vpn.example.com" - allows all traffic to this host
          - "192.0.2.1:51820" - allows UDP traffic to port 51820
          - "vpn.example.com:443" - allows UDP traffic to port 443
      '';
      example = [ "vpn.example.com:51820" "backup-vpn.example.org" "192.0.2.1:443" ];
    };

    vpnInterface = mkOption {
      type = types.str;
      description = "The virtual network interface for your VPN tunnel.";
      example = "wg0";
    };

    allowedServices = mkOption {
      type = types.listOf (types.submodule {
        options = {
          port = mkOption {
            type = types.port;
            description = "TCP port to allow";
          };
          sources = mkOption {
            type = types.listOf types.str;
            description = "List of source IP addresses or subnets allowed to access this port";
            example = [ "192.168.1.100" "192.168.1.0/24" ];
          };
        };
      });
      default = [];
      description = ''
        Additional services to allow through the firewall from specific sources.
        Each service specifies a TCP port and a list of allowed source IPs/subnets.
      '';
      example = [
        { port = 8080; sources = [ "192.168.1.100" "192.168.1.50" ]; }
        { port = 9091; sources = [ "192.168.1.0/24" ]; }
      ];
    };

    vpnIncomingPorts = mkOption {
      type = types.submodule {
        options = {
          tcp = mkOption {
            type = types.listOf (types.either types.port types.str);
            default = [];
            description = "TCP ports or port ranges to allow incoming on VPN interface";
            example = [ 6881 "6881-6889" 8080 ];
          };
          udp = mkOption {
            type = types.listOf (types.either types.port types.str);
            default = [];
            description = "UDP ports or port ranges to allow incoming on VPN interface";
            example = [ 6881 "6881-6889" ];
          };
        };
      };
      default = { tcp = []; udp = []; };
      description = ''
        Ports to allow for incoming connections through the VPN interface.
        Useful for services like torrenting that need to accept connections from the internet.
        Supports both individual ports and port ranges (e.g., "6881-6889").
      '';
      example = {
        tcp = [ 6881 "8000-9000" ];
        udp = [ 6881 ];
      };
    };

    lanDns = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption ''
            a LAN-facing Unbound resolver. Listens on `listenAddress`,
            answers queries from `allowSubnets`, and forces upstream
            queries out via the VPN interface for privacy. Pair with an
            in-cluster CoreDNS (or any forwarder) that delegates `.` to
            this address.
          '';
          listenAddress = mkOption {
            type = types.str;
            default = "";
            description = "LAN IP address Unbound should bind to (UDP+TCP/53).";
            example = "192.168.1.132";
          };
          allowSubnets = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              Source subnets (CIDR) allowed to query the resolver.
              Anything else gets refused at the Unbound access-control
              layer AND the nftables input chain.
            '';
            example = [ "192.168.1.0/24" "10.42.0.0/16" ];
          };
          upstreamServers = mkOption {
            type = types.listOf types.str;
            default = [
              "9.9.9.9@853#dns.quad9.net"
              "149.112.112.112@853#dns.quad9.net"
              "1.1.1.1@853#cloudflare-dns.com"
              "1.0.0.1@853#cloudflare-dns.com"
            ];
            description = ''
              Upstream DoT resolvers, in Unbound `addr@port#authname`
              format. Queries to these addresses egress via
              `vpnInterface` (set via Unbound's `outgoing-interface:`).
            '';
          };
        };
      };
      default = { enable = false; listenAddress = ""; allowSubnets = []; };
      description = ''
        Optional LAN-facing Unbound resolver. Designed for
        download-server-1: an in-cluster CoreDNS forwards LAN-bound
        recursion here, and Unbound exits upstream over the existing
        WireGuard tunnel.
      '';
    };
  };

  config = mkIf cfg.enable (let
      githubDomains = concatStringsSep " " cfg.exceptions.domains.github;
      nixDomains = concatStringsSep " " cfg.exceptions.domains.nix;

      # Parse VPN endpoints to extract hosts (without ports) for DNS resolution
      parseEndpoint = endpoint:
        let
          parts = lib.splitString ":" endpoint;
          host = builtins.head parts;
          port = if builtins.length parts > 1 then builtins.elemAt parts 1 else null;
        in
        { inherit host port; };

      parsedEndpoints = map parseEndpoint cfg.vpnEndpoints;
      vpnEndpointHosts = concatStringsSep " " (map (e: e.host) parsedEndpoints);

      # Separate endpoints with and without ports for different nftables rules
      endpointsWithPorts = builtins.filter (e: e.port != null) parsedEndpoints;
      endpointsWithoutPorts = builtins.filter (e: e.port == null) parsedEndpoints;

      updateScript = pkgs.writeShellApplication {
        name = "update-nft-sets-proxy";

        runtimeInputs = with pkgs; [
          dnsutils
          nftables
        ];

        text = let
          # Build endpoint-to-port mappings for the script
          endpointsWithPortsStr = lib.concatMapStringsSep "\n" (e:
            ''ENDPOINTS_PORT_${e.port}="''${ENDPOINTS_PORT_${e.port}:-} ${e.host}"''
          ) endpointsWithPorts;

          endpointsWithoutPortsStr = if (builtins.length endpointsWithoutPorts) > 0
            then ''ENDPOINTS_NO_PORT="${concatStringsSep " " (map (e: e.host) endpointsWithoutPorts)}"''
            else "";
        in ''
          set -euo pipefail
          declare -A DOMAINS
          DOMAINS["nix_caches"]="${nixDomains}"
          DOMAINS["github_ips"]="${githubDomains}"

          # VPN endpoints organized by port
          ${endpointsWithPortsStr}
          ${endpointsWithoutPortsStr}

          get_ips() {
              local entries=$1
              for entry in $entries; do
                  # Check if entry is already an IP address
                  if echo "$entry" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                      # It's already an IP, output it directly
                      echo "$entry"
                  else
                      # It's a hostname, resolve it with timeout
                      dig +short +time=5 +tries=2 A "$entry" 2>/dev/null || true
                  fi
              done | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u
          }

          # Update standard sets (nix_caches, github_ips)
          for set_name in "''${!DOMAINS[@]}"; do
              echo "Updating set: $set_name"
              NEW_IPS=$(get_ips "''${DOMAINS[$set_name]}")
              if [ -z "$NEW_IPS" ]; then
                  echo "Warning: Could not resolve any IPs for domains in set $set_name. Skipping."
                  continue
              fi
              # Update the set: flush and add new IPs
              nft flush set inet filter "$set_name"
              nft add element inet filter "$set_name" "{ $(echo "$NEW_IPS" | tr '\n' ',' | sed 's/,$//' ) }"
              echo "Successfully updated set $set_name."
          done

          # Update port-specific VPN endpoint sets
          ${lib.concatMapStringsSep "\n" (port: ''
          if [ -n "''${ENDPOINTS_PORT_${port}:-}" ]; then
              echo "Updating set: vpn_endpoints_port_${port}"
              NEW_IPS=$(get_ips "$ENDPOINTS_PORT_${port}")
              if [ -n "$NEW_IPS" ]; then
                  nft flush set inet filter "vpn_endpoints_port_${port}"
                  nft add element inet filter "vpn_endpoints_port_${port}" "{ $(echo "$NEW_IPS" | tr '\n' ',' | sed 's/,$//' ) }"
                  echo "Successfully updated set vpn_endpoints_port_${port}."
              else
                  echo "Warning: Could not resolve any IPs for vpn_endpoints_port_${port}. Skipping."
              fi
          fi
          '') (lib.unique (map (e: e.port) endpointsWithPorts))}

          # Update generic VPN endpoints (no port specified)
          ${if (builtins.length endpointsWithoutPorts) > 0 then ''
          if [ -n "''${ENDPOINTS_NO_PORT:-}" ]; then
              echo "Updating set: vpn_endpoints"
              NEW_IPS=$(get_ips "$ENDPOINTS_NO_PORT")
              if [ -n "$NEW_IPS" ]; then
                  nft flush set inet filter "vpn_endpoints"
                  nft add element inet filter "vpn_endpoints" "{ $(echo "$NEW_IPS" | tr '\n' ',' | sed 's/,$//' ) }"
                  echo "Successfully updated set vpn_endpoints."
              else
                  echo "Warning: Could not resolve any IPs for vpn_endpoints. Skipping."
              fi
          fi
          '' else ""}

          echo "All sets updated."
        '';
      };
    in
    {
      environment.systemPackages = with pkgs; [
        iproute2
        microsocks
        nftables
      ];

      # Create a microsocks service for the first LAN interface
      systemd.services."microsocks-proxy" = {
        after = [ "network-online.target" ];
        description = "SOCKS5 Proxy with dynamic IP binding";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "5s";

          ExecStart = ''
            ${pkgs.bash}/bin/bash -c '
              set -e
              LAN_IF="${builtins.head cfg.lanInterfaces}"
              echo "Attempting to find IP for interface $LAN_IF..."

              # This command finds the IPv4 address for the specified interface.
              LISTEN_IP=$(${pkgs.iproute2}/bin/ip -4 addr show dev "$LAN_IF" | ${pkgs.gnugrep}/bin/grep -oP "inet \\K[\\d.]+")

              if [ -z "$LISTEN_IP" ]; then
                echo "FATAL: Could not find IPv4 address for $LAN_IF. Cannot start proxy." >&2
                exit 1
              fi

              echo "microsocks starting, listening on $LISTEN_IP:${toString cfg.proxy.port}"

              # The exec command replaces the shell process with microsocks.
              exec ${pkgs.microsocks}/bin/microsocks \
                -i "$LISTEN_IP" \
                -p ${toString cfg.proxy.port} \
                ${if cfg.proxy.auth == "none" then "" else "-u ${cfg.proxy.auth}"}
            '
          '';
        };
      };

      networking.firewall.enable = lib.mkForce false;

      networking.nftables = {
        enable = true;

        ruleset = let
          # Get unique ports from endpoints with ports
          uniquePorts = lib.unique (map (e: e.port) endpointsWithPorts);

          # Group endpoints by port for initial population
          endpointsByPort = lib.listToAttrs (map (port:
            {
              name = port;
              value = lib.filter (e: e.port == port) endpointsWithPorts;
            }
          ) uniquePorts);

          # Generate set definitions with initial IPs for endpoints that are already IPs
          portSetDefinitions = lib.concatMapStringsSep "\n" (port:
            let
              endpoints = endpointsByPort.${port};
              # Filter for hosts that are already IP addresses
              initialIPs = lib.filter (e: builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$" e.host != null) endpoints;
              ipList = lib.concatMapStringsSep ", " (e: e.host) initialIPs;
              elements = if (builtins.length initialIPs) > 0 then " elements = { ${ipList} };" else "";
            in
            "              set vpn_endpoints_port_${port} { type ipv4_addr; flags dynamic;${elements} }"
          ) uniquePorts;

          # Generate rules for each port
          portRules = lib.concatMapStringsSep "\n" (port:
            "                  ip daddr @vpn_endpoints_port_${port} udp dport ${port} accept"
          ) uniquePorts;
        in ''
          table inet filter {
              set github_ips { type ipv4_addr; flags dynamic; }
              set nix_caches { type ipv4_addr; flags dynamic; }
              ${if (builtins.length endpointsWithoutPorts) > 0 then
                let
                  # Filter for hosts that are already IP addresses
                  initialIPs = lib.filter (e: builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$" e.host != null) endpointsWithoutPorts;
                  ipList = lib.concatMapStringsSep ", " (e: e.host) initialIPs;
                  elements = if (builtins.length initialIPs) > 0 then " elements = { ${ipList} };" else "";
                in
                "set vpn_endpoints { type ipv4_addr; flags dynamic;${elements} }"
              else ""}
              ${portSetDefinitions}

              chain input {
                  type filter hook input priority 0; policy drop;
                  ct state established,related accept
                  iifname "lo" accept
                  ${lib.concatStringsSep "\n" (lib.map (lanInterface: "  iifname \"${lanInterface}\" tcp dport 22 accept") cfg.lanInterfaces)}
                  ${lib.concatMapStringsSep "\n" (lanInterface:
                    lib.concatMapStringsSep "\n" (lanSubnet:
                      "  iifname \"${lanInterface}\" ip saddr ${lanSubnet} tcp dport ${toString cfg.proxy.port} accept"
                    ) cfg.lanSubnets
                  ) cfg.lanInterfaces}

                  # == ADDITIONAL ALLOWED SERVICES ==
                  ${lib.concatMapStringsSep "\n" (service:
                    lib.concatMapStringsSep "\n" (source:
                      lib.concatStringsSep "\n" (lib.map (lanInterface:
                        "  iifname \"${lanInterface}\" ip saddr ${source} tcp dport ${toString service.port} accept"
                      ) cfg.lanInterfaces)
                    ) service.sources
                  ) cfg.allowedServices}

                  # == VPN ENDPOINT RESPONSES ==
                  # Accept incoming UDP responses from VPN endpoints on specific ports
                  ${lib.concatMapStringsSep "\n" (port:
                    "  ip saddr @vpn_endpoints_port_${port} udp sport ${port} accept"
                  ) uniquePorts}
                  # Accept incoming responses from generic VPN endpoints
                  ${if (builtins.length endpointsWithoutPorts) > 0 then "ip saddr @vpn_endpoints accept" else ""}

                  # == LAN DNS RESOLVER (lanDns) ==
                  # Accept DNS queries (UDP+TCP/53) from allowed subnets
                  # to the Unbound listener bound on listenAddress.
                  ${lib.optionalString cfg.lanDns.enable (
                    lib.concatMapStringsSep "\n" (lanInterface:
                      lib.concatMapStringsSep "\n" (sub: ''
                        iifname "${lanInterface}" ip saddr ${sub} ip daddr ${cfg.lanDns.listenAddress} udp dport 53 accept
                        iifname "${lanInterface}" ip saddr ${sub} ip daddr ${cfg.lanDns.listenAddress} tcp dport 53 accept
                      '') cfg.lanDns.allowSubnets
                    ) cfg.lanInterfaces
                  )}

                  # == VPN INCOMING PORTS ==
                  # Accept incoming TCP connections on VPN interface
                  ${lib.concatMapStringsSep "\n" (port:
                    "  iifname \"${cfg.vpnInterface}\" tcp dport ${toString port} accept"
                  ) cfg.vpnIncomingPorts.tcp}
                  # Accept incoming UDP connections on VPN interface
                  ${lib.concatMapStringsSep "\n" (port:
                    "  iifname \"${cfg.vpnInterface}\" udp dport ${toString port} accept"
                  ) cfg.vpnIncomingPorts.udp}
              }

              chain output {
                  type filter hook output priority 0; policy drop;
                  ct state established,related accept
                  oifname "lo" accept
                  ${lib.concatMapStringsSep "\n" (lanInterface:
                    lib.concatMapStringsSep "\n" (lanSubnet:
                      "  oifname \"${lanInterface}\" ip daddr ${lanSubnet} accept"
                    ) cfg.lanSubnets
                  ) cfg.lanInterfaces}
                  oifname "${cfg.vpnInterface}" accept

                  # == EXCEPTIONS FOR THE GATEWAY ITSELF ==
                  ${lib.concatStringsSep "\n" (lib.map (lanInterface: "  oifname \"${lanInterface}\" udp dport 53 ip daddr { ${concatStringsSep ", " cfg.exceptions.dnsServers} } accept") cfg.lanInterfaces)}
                  ${lib.concatStringsSep "\n" (lib.map (lanInterface: "  oifname \"${lanInterface}\" ip daddr @nix_caches accept") cfg.lanInterfaces)}
                  ${lib.concatStringsSep "\n" (lib.map (lanInterface: "  oifname \"${lanInterface}\" ip daddr @github_ips accept") cfg.lanInterfaces)}

                  # == VPN ENDPOINT ACCESS ==
                  # Port-specific VPN endpoints (UDP only)
                  ${portRules}
                  # Generic VPN endpoints (all traffic)
                  ${if (builtins.length endpointsWithoutPorts) > 0 then "ip daddr @vpn_endpoints accept" else ""}
              }
          }
        '';
      };

      systemd.timers."update-nft-sets" = {
        description = "Timer to update nftables IP sets for VPN exceptions";
        wantedBy = [ "timers.target" ];

        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = cfg.updateFrequency;
          Persistent = true;
        };
      };

      systemd.services."update-nft-sets" = {
        # Prefer to run after VPN is up for DNS resolution, but don't require it
        after = [ "network-online.target" "wg-quick-${cfg.vpnInterface}.service" ];
        description = "Update nftables IP sets for VPN exceptions";
        wants = [ "network-online.target" ];

        serviceConfig = {
          ExecStart = "${updateScript}/bin/update-nft-sets-proxy";
          Type = "oneshot";
          # Add timeout for DNS resolution in case VPN isn't up yet
          TimeoutStartSec = "2min";
        };
      };

      # ====================================================================
      # LAN DNS resolver (services.proxyVpnGateway.lanDns)
      # ====================================================================
      # Unbound listens on lanDns.listenAddress, answers queries from
      # lanDns.allowSubnets, and routes upstream queries (DoT to Quad9 /
      # Cloudflare by default) out via the VPN interface using Unbound's
      # `outgoing-interface:` directive bound to the VPN's source IP.
      users.users.unbound = lib.mkIf cfg.lanDns.enable {
        isSystemUser = true;
        group = "unbound";
        home = "/var/lib/unbound-lan-dns";
        createHome = true;
      };
      users.groups.unbound = lib.mkIf cfg.lanDns.enable {};

      systemd.services.unbound-lan-dns = lib.mkIf cfg.lanDns.enable (let
        unboundConfig = pkgs.writeText "unbound-lan-dns.conf" ''
          server:
              # Disable chroot — we run under systemd sandboxing,
              # ProtectSystem + PrivateTmp already isolate the daemon.
              chroot: ""
              directory: "/var/lib/unbound-lan-dns"
              pidfile: "/var/lib/unbound-lan-dns/unbound.pid"
              username: ""

              # Bind to LAN IP only.
              interface: ${cfg.lanDns.listenAddress}
              port: 53
              do-ip4: yes
              do-ip6: no
              do-udp: yes
              do-tcp: yes

              # Recursion sources upstream queries via the VPN tunnel.
              # We bind outgoing sockets to 0.0.0.0; the kernel chooses
              # the route to upstreamServers — those routes go via
              # `${cfg.vpnInterface}` because wg-quick installed
              # `AllowedIPs = 0.0.0.0/0` on that interface.
              outgoing-interface: 0.0.0.0

              # Access control: deny by default, allow listed subnets.
              ${lib.concatMapStringsSep "\n    " (sub:
                "access-control: ${sub} allow"
              ) cfg.lanDns.allowSubnets}
              access-control: 0.0.0.0/0 refuse

              # Caching
              num-threads: 2
              msg-cache-size: 64m
              rrset-cache-size: 128m
              cache-min-ttl: 60
              cache-max-ttl: 86400
              prefetch: yes
              prefetch-key: yes
              serve-expired: yes
              serve-expired-ttl: 3600

              # Security
              hide-identity: yes
              hide-version: yes
              harden-glue: yes
              harden-dnssec-stripped: yes
              harden-below-nxdomain: yes
              harden-referral-path: yes
              use-caps-for-id: yes

              # DNSSEC
              auto-trust-anchor-file: "/var/lib/unbound-lan-dns/root.key"
              val-clean-additional: yes

              # Logging
              verbosity: 1
              log-queries: no

              # DoT trust anchor
              tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt

          forward-zone:
              name: "."
              forward-tls-upstream: yes
              ${lib.concatMapStringsSep "\n    " (server:
                "forward-addr: ${server}"
              ) cfg.lanDns.upstreamServers}
        '';
      in {
        description = "Unbound LAN DNS resolver (egress via VPN)";
        after = [ "network-online.target" "wg-quick-${cfg.vpnInterface}.service" ];
        wants = [ "network-online.target" "wg-quick-${cfg.vpnInterface}.service" ];
        wantedBy = [ "multi-user.target" ];

        preStart = ''
          install -d -o unbound -g unbound -m 0750 /var/lib/unbound-lan-dns
          if [ ! -f /var/lib/unbound-lan-dns/root.key ]; then
            ${pkgs.unbound}/bin/unbound-anchor \
              -a /var/lib/unbound-lan-dns/root.key \
              -c /etc/ssl/certs/ca-certificates.crt || true
            chown unbound:unbound /var/lib/unbound-lan-dns/root.key
          fi
        '';

        serviceConfig = {
          Type = "simple";
          User = "unbound";
          Group = "unbound";
          ExecStart = "${pkgs.unbound}/bin/unbound -d -c ${unboundConfig}";
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          Restart = "on-failure";
          RestartSec = "5s";

          # Needs CAP_NET_BIND_SERVICE for :53; ProtectSystem + sandbox.
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ "/var/lib/unbound-lan-dns" ];
        };
      });

      # =====================================================================
      # DNS bootstrap bypass
      # =====================================================================
      # wg-quick (AllowedIPs=0.0.0.0/0) installs an ip rule sending all
      # unmarked traffic through the VPN routing table. This includes the
      # system-resolved queries to `exceptions.dnsServers` — meaning the
      # host can't resolve its OWN VPN endpoint hostname / nix substituters
      # / health probes until the VPN tunnel is up. Chicken-and-egg if the
      # tunnel ever fails: bootstrap requires DNS, DNS requires VPN.
      #
      # Pin `exceptions.dnsServers` to the main routing table via a
      # higher-priority ip rule so those few addresses always egress via
      # the physical interface, even when the VPN is down. Privacy leak
      # is bounded to a known set of public resolvers used only by the
      # host's bootstrap stub (Unbound's recursion still goes via VPN).
      systemd.services.proxy-vpn-dns-bootstrap-routes = {
        description = "Pin DNS exception IPs to main routing table (bypass VPN)";
        wantedBy = [ "multi-user.target" "network-pre.target" ];
        before = [ "wg-quick-${cfg.vpnInterface}.service" "network.target" ];
        after = [ "network-pre.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "proxy-vpn-dns-bootstrap-routes-up" ''
            set +e
            ${lib.concatMapStringsSep "\n" (ip: ''
              ${pkgs.iproute2}/bin/ip rule del to ${ip}/32 lookup main priority 5000 2>/dev/null
              ${pkgs.iproute2}/bin/ip rule add to ${ip}/32 lookup main priority 5000
            '') cfg.exceptions.dnsServers}
            exit 0
          '';
          ExecStop = pkgs.writeShellScript "proxy-vpn-dns-bootstrap-routes-down" ''
            ${lib.concatMapStringsSep "\n" (ip: ''
              ${pkgs.iproute2}/bin/ip rule del to ${ip}/32 lookup main priority 5000 2>/dev/null
            '') cfg.exceptions.dnsServers}
            exit 0
          '';
        };
      };
    });
}
