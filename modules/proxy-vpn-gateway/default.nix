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

    lanInterface = mkOption {
      type = types.str;
      description = "The physical network interface connected to the LAN.";
      example = "enp3s0";
    };

    lanSubnet = mkOption {
      type = types.str;
      description = "The IP subnet for your local LAN.";
      example = "192.168.1.0/24";
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

    vpnInterface = mkOption {
      type = types.str;
      description = "The virtual network interface for your VPN tunnel.";
      example = "wg0";
    };
  };

  config = mkIf cfg.enable {
    let
      githubDomains = concatStringsSep " " cfg.exceptions.domains.github;
      nixDomains = concatStringsSep " " cfg.exceptions.domains.nix;

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

          get_ips() {
              local domains=$1
              for domain in $domains; do
                  dig +short A "$domain"
              done | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u
          }

          for set_name in "''${!DOMAINS[@]}"; do
              echo "Updating set: $set_name"
              NEW_IPS=$(get_ips "''${DOMAINS[$set_name]}")
              if [ -z "$NEW_IPS" ]; then
                  echo "Warning: Could not resolve any IPs for domains in set $set_name. Skipping."
                  continue
              fi
              # Atomically update the set
              nft add set inet filter "''${set_name}_temp" { type ipv4_addr\; flags timeout\; }
              nft add element inet filter "''${set_name}_temp" { $(echo $NEW_IPS | tr '\n' ',') }
              nft flush set inet filter "$set_name"
              nft add element inet filter "$set_name" { @''${set_name}_temp }
              nft delete set inet filter "''${set_name}_temp"
              echo "Successfully updated set $set_name."
          done
          echo "All sets updated."
        '';
      };

      microsocksLauncher = pkgs.writeShellApplication {
        name = "microsocks-launcher";

        runtimeInputs = with pkgs; [
          iproute2
          microsocks
        ];

        text = ''
          #!/bin/sh
          set -e

          LAN_IF="''${1?LAN interface argument is missing}"
          PROXY_PORT="''${2?Proxy port argument is missing}"
          PROXY_AUTH="$3"

          echo "microsocks-launcher: Attempting to find IP for interface ''${LAN_IF}..."

          LISTEN_IP=$(ip -4 addr show dev "''${LAN_IF}" | grep -oP "inet \\K[\\d.]+")

          if [ -z "$LISTEN_IP" ]; then
            echo "FATAL: Could not find IPv4 address for ''${LAN_IF}. Cannot start proxy." >&2
            exit 1
          fi

          echo "microsocks-launcher: Starting proxy, listening on ''${LISTEN_IP}:''${PROXY_PORT}"

          # Build the authentication argument conditionally.
          AUTH_ARG=""
          if [ "''${PROXY_AUTH}" != "none" ] && [ -n "''${PROXY_AUTH}" ]; then
              AUTH_ARG="-u ''${PROXY_AUTH}"
          fi

          # Use 'exec' to replace the shell process with microsocks.
          # 'microsocks' is in the PATH thanks to runtimeInputs.
          exec microsocks -i "$LISTEN_IP" -p "$PROXY_PORT" $AUTH_ARG
        '';
    in
    {
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
              echo "Attempting to find IP for interface ${cfg.lanInterface}..."

              # This command finds the IPv4 address for the specified interface.
              LISTEN_IP=$(ip -4 addr show dev ${cfg.lanInterface} | grep -oP "inet \\K[\\d.]+")

              if [ -z "$LISTEN_IP" ]; then
                echo "FATAL: Could not find IPv4 address for ${cfg.lanInterface}. Cannot start proxy." >&2
                exit 1
              fi

              echo "microsocks starting, listening on $LISTEN_IP:${toString cfg.proxy.port}"

              # The 'exec' command replaces the shell process with microsocks.
              exec ${pkgs.microsocks}/bin/microsocks \
                -i "$LISTEN_IP" \
                -p ${toString cfg.proxy.port} \
                ${# Nix's 'if' to conditionally add the authentication argument.
                  if cfg.proxy.auth == "none" then "" else "-u ${cfg.proxy.auth}"
                }
            '
          '';
        };
      };

      networking.nftables = {
        enable = true;

        ruleset = ''
          table inet filter {
              set github_ips { type ipv4_addr; flags dynamic; }
              set nix_caches { type ipv4_addr; flags dynamic; }

              chain input {
                  type filter hook input priority 0; policy drop;
                  ct state established,related accept
                  iifname "lo" accept
                  iifname ${cfg.lanInterface} tcp dport 22 accept
                  iifname ${cfg.lanInterface} ip saddr ${cfg.lanSubnet} tcp dport ${toString cfg.proxy.port} accept
              }

              chain output {
                  type filter hook output priority 0; policy drop;
                  ct state established,related accept
                  oifname "lo" accept
                  oifname ${cfg.lanInterface} ip daddr ${cfg.lanSubnet} accept
                  oifname ${cfg.vpnInterface} accept

                  # == EXCEPTIONS FOR THE GATEWAY ITSELF ==
                  oifname ${cfg.lanInterface} udp dport 53 ip daddr { ${concatStringsSep ", " cfg.exceptions.dnsServers} } accept
                  oifname ${cfg.lanInterface} ip daddr @nix_caches accept
                  oifname ${cfg.lanInterface} ip daddr @github_ips accept
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
    };
}
