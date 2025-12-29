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
      description = "List of VPN endpoint hostnames or IP addresses that should be allowed through the firewall.";
      example = [ "vpn.example.com" "backup-vpn.example.org" "192.0.2.1" "198.51.100.42" ];
    };

    vpnInterface = mkOption {
      type = types.str;
      description = "The virtual network interface for your VPN tunnel.";
      example = "wg0";
    };
  };

  config = mkIf cfg.enable (let
      githubDomains = concatStringsSep " " cfg.exceptions.domains.github;
      nixDomains = concatStringsSep " " cfg.exceptions.domains.nix;
      vpnEndpoints = concatStringsSep " " cfg.vpnEndpoints;

      updateScript = pkgs.writeShellApplication {
        name = "update-nft-sets-proxy";

        runtimeInputs = with pkgs; [
          dnsutils
          nftables
        ];

        text = ''
          set -euo pipefail
          declare -A DOMAINS
          DOMAINS["nix_caches"]="${nixDomains}"
          DOMAINS["github_ips"]="${githubDomains}"
          ${if (builtins.length cfg.vpnEndpoints) > 0 then ''DOMAINS["vpn_endpoints"]="${vpnEndpoints}"'' else ""}

          get_ips() {
              local entries=$1
              for entry in $entries; do
                  # Check if entry is already an IP address
                  if echo "$entry" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                      # It's already an IP, output it directly
                      echo "$entry"
                  else
                      # It's a hostname, resolve it
                      dig +short A "$entry"
                  fi
              done | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u
          }

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

        ruleset = ''
          table inet filter {
              set github_ips { type ipv4_addr; flags dynamic; }
              set nix_caches { type ipv4_addr; flags dynamic; }
              ${if (builtins.length cfg.vpnEndpoints) > 0 then "set vpn_endpoints { type ipv4_addr; flags dynamic; }" else ""}

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
                  # Allow VPN endpoint connections on any interface (needed for VPN to connect)
                  ${if (builtins.length cfg.vpnEndpoints) > 0 then "ip daddr @vpn_endpoints accept" else ""}
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
        after = [ "network-online.target" ];
        description = "Update nftables IP sets for VPN exceptions";
        wants = [ "network-online.target" ];

        serviceConfig = {
          ExecStart = "${updateScript}/bin/update-nft-sets-proxy";
          Type = "oneshot";
        };
      };
    });
}
