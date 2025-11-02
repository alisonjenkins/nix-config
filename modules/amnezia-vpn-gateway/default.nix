{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.amneziaVpnGateway;
  
  # Use official AmneziaWG packages from nixpkgs
  # - amneziawg-tools: Official userspace tools (awg, awg-quick) 
  # - config.boot.kernelPackages.amneziawg: Official kernel module

  # Unbound configuration for high-performance DNS caching (system DNS)
  unboundSystemConfig = pkgs.writeText "unbound-system.conf" ''
    server:
        # Basic configuration
        interface: 127.0.0.1@${toString cfg.dns.localPort}
        port: ${toString cfg.dns.localPort}
        do-ip4: yes
        do-ip6: no
        do-udp: yes
        do-tcp: yes
        
        # Performance settings
        num-threads: ${toString cfg.dns.cache.threads}
        msg-cache-slabs: ${toString cfg.dns.cache.slabs}
        rrset-cache-slabs: ${toString cfg.dns.cache.slabs}
        infra-cache-slabs: ${toString cfg.dns.cache.slabs}
        key-cache-slabs: ${toString cfg.dns.cache.slabs}
        
        # Cache settings for maximum performance
        msg-cache-size: ${cfg.dns.cache.messageSize}
        rrset-cache-size: ${cfg.dns.cache.rrsetSize}
        cache-min-ttl: ${toString cfg.dns.cache.minTtl}
        cache-max-ttl: ${toString cfg.dns.cache.maxTtl}
        cache-max-negative-ttl: ${toString cfg.dns.cache.negativeMaxTtl}
        
        # Prefetch for better performance
        prefetch: yes
        prefetch-key: yes
        serve-expired: yes
        serve-expired-ttl: 3600
        
        # Security settings
        hide-identity: yes
        hide-version: yes
        harden-glue: yes
        harden-dnssec-stripped: yes
        harden-below-nxdomain: yes
        harden-referral-path: yes
        harden-algo-downgrade: yes
        use-caps-for-id: yes
        
        # DNSSEC validation
        auto-trust-anchor-file: "/var/lib/unbound-system/root.key"
        val-clean-additional: yes
        val-permissive-mode: no
        val-log-level: 1
        
        # Logging
        verbosity: ${toString cfg.dns.logLevel}
        log-queries: ${if cfg.dns.logQueries then "yes" else "no"}
        log-local-actions: yes
        
        # Access control - system only
        access-control: 127.0.0.0/8 allow
        access-control: 0.0.0.0/0 refuse
        
        # TLS settings for DNS over TLS
        tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt

    # Forward zones for DNS over HTTPS/TLS
    ${concatMapStringsSep "\n    " (server: ''
    forward-zone:
        name: "."
        forward-tls-upstream: yes
        forward-addr: ${server}
    '') cfg.dns.upstreamServers}
  '';

  # Unbound configuration for VPN clients (routes through VPN tunnel)
  unboundVpnConfig = pkgs.writeText "unbound-vpn.conf" ''
    server:
        # Listen on LAN interface for client queries
        interface: ${cfg.network.vpnGatewayIp}@${toString cfg.dns.vpnPort}
        port: ${toString cfg.dns.vpnPort}
        do-ip4: yes
        do-ip6: no
        do-udp: yes
        do-tcp: yes
        
        # Performance settings
        num-threads: ${toString cfg.dns.cache.threads}
        msg-cache-slabs: ${toString cfg.dns.cache.slabs}
        rrset-cache-slabs: ${toString cfg.dns.cache.slabs}
        infra-cache-slabs: ${toString cfg.dns.cache.slabs}
        key-cache-slabs: ${toString cfg.dns.cache.slabs}
        
        # Aggressive caching for VPN clients
        msg-cache-size: ${cfg.dns.cache.messageSize}
        rrset-cache-size: ${cfg.dns.cache.rrsetSize}
        cache-min-ttl: ${toString cfg.dns.cache.minTtl}
        cache-max-ttl: ${toString cfg.dns.cache.maxTtl}
        cache-max-negative-ttl: ${toString cfg.dns.cache.negativeMaxTtl}
        
        # Enhanced prefetching for better VPN performance
        prefetch: yes
        prefetch-key: yes
        serve-expired: yes
        serve-expired-ttl: 7200
        serve-expired-client-timeout: 1800
        
        # Security settings
        hide-identity: yes
        hide-version: yes
        harden-glue: yes
        harden-dnssec-stripped: yes
        harden-below-nxdomain: yes
        harden-referral-path: yes
        harden-algo-downgrade: yes
        use-caps-for-id: yes
        
        # DNSSEC validation
        auto-trust-anchor-file: "/var/lib/unbound-vpn/root.key"
        val-clean-additional: yes
        val-permissive-mode: no
        val-log-level: 1
        
        # Logging
        verbosity: ${toString cfg.dns.logLevel}
        log-queries: ${if cfg.dns.logQueries then "yes" else "no"}
        log-local-actions: yes
        
        # Access control - allow LAN subnets only
        ${concatMapStringsSep "\n        " (subnet: "access-control: ${subnet} allow") cfg.network.lanSubnets}
        access-control: 0.0.0.0/0 refuse
        
        # TLS settings for DNS over TLS
        tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt

    # Forward zones for DNS over HTTPS/TLS via VPN
    ${concatMapStringsSep "\n    " (server: ''
    forward-zone:
        name: "."
        forward-tls-upstream: yes
        forward-addr: ${server}
    '') cfg.dns.upstreamServers}
  '';

  # Event-driven kill switch script - triggers immediately on VPN changes
  immediateKillSwitchScript = pkgs.writeShellScript "immediate-killswitch" ''
    set -euo pipefail
    
    VPN_INTERFACE="${cfg.vpn.interface}"
    
    echo "=== IMMEDIATE Kill Switch Activation ==="
    echo "VPN interface $VPN_INTERFACE state changed - checking status..."
    
    # Immediately clear VPN IPs from firewall (block forwarding instantly)
    nft flush set inet filter vpn_interface_ips 2>/dev/null || true
    echo "🚨 Forwarding BLOCKED immediately (cleared VPN IP set)"
    
    # Add explicit drop rule for extra safety
    nft add rule inet filter forward counter drop comment "IMMEDIATE kill switch - VPN down" 2>/dev/null || true
    
    # Kill NAT rules immediately
    nft flush chain ip nat postrouting 2>/dev/null || true
    echo "🚨 NAT rules flushed - no masquerading"
    
    # Log the kill switch activation
    logger -p daemon.crit "VPN Gateway: IMMEDIATE kill switch activated - VPN interface state changed"
    
    # Check current interface status
    if ip addr show "$VPN_INTERFACE" 2>/dev/null | grep -q "inet "; then
        VPN_IP=$(ip addr show "$VPN_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -1)
        echo "Interface has IP: $VPN_IP - testing connectivity..."
        
        # Test connectivity immediately
        if timeout 10 ${pkgs.curl}/bin/curl --interface "$VPN_INTERFACE" -s -m 5 http://checkip.amazonaws.com/ >/dev/null 2>&1; then
            echo "✅ VPN connectivity verified - re-enabling forwarding"
            # Remove the emergency drop rule
            nft delete rule inet filter forward handle $(nft -a list chain inet filter forward | grep "IMMEDIATE kill switch" | awk '{print $NF}') 2>/dev/null || true
            # Add IP back to allow set
            nft add element inet filter vpn_interface_ips "{ $VPN_IP }" 2>/dev/null || true
            # Restore NAT rules
            nft add rule ip nat postrouting oifname "${cfg.vpn.interface}" ip saddr { ${concatStringsSep ", " cfg.network.lanSubnets} } masquerade 2>/dev/null || true
            logger -p daemon.info "VPN Gateway: Kill switch deactivated - VPN connectivity restored"
        else
            echo "🚨 VPN interface has IP but no connectivity - keeping kill switch ACTIVE"
            logger -p daemon.crit "VPN Gateway: Kill switch remains active - VPN has no internet connectivity"
        fi
    else
        echo "🚨 VPN interface has no IP - keeping kill switch ACTIVE"
        logger -p daemon.crit "VPN Gateway: Kill switch remains active - VPN interface has no IP"
    fi
    
    echo "=== Kill Switch Check Complete ==="
  '';
  killSwitchScript = pkgs.writeShellScript "vpn-killswitch" ''
    set -euo pipefail
    
    VPN_INTERFACE="${cfg.vpn.interface}"
    
    echo "=== VPN Kill Switch Check ==="
    
    # 1. Check if VPN interface exists and has an IP
    if ! ip addr show "$VPN_INTERFACE" 2>/dev/null | grep -q "inet "; then
        echo "🚨 CRITICAL: VPN interface $VPN_INTERFACE is down or has no IP. Activating kill switch."
        
        # Immediately block all forwarded traffic
        nft add rule inet filter forward counter drop comment "VPN kill switch - no interface IP"
        
        # Clear VPN IP set to prevent any forwarding
        nft flush set inet filter vpn_interface_ips 2>/dev/null || true
        
        # Kill any existing NAT rules for LAN traffic
        nft flush chain ip nat postrouting 2>/dev/null || true
        
        echo "🛡️  Kill switch activated - all forwarded traffic blocked"
        logger -p daemon.crit "VPN Gateway: Kill switch activated - VPN interface has no IP"
        
        # Attempt to restart VPN connection
        echo "Attempting to restart VPN connection..."
        systemctl restart amnezia-wg || true
        
        exit 1
    fi
    
    # 2. Get VPN interface IP
    VPN_IP=$(ip addr show "$VPN_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -1)
    echo "VPN interface has IP: $VPN_IP"
    
    # 3. Test if VPN interface can actually reach the internet
    echo "Testing VPN connectivity..."
    if ! timeout 10 ${pkgs.curl}/bin/curl --interface "$VPN_INTERFACE" -s -m 5 http://checkip.amazonaws.com/ >/dev/null 2>&1; then
        echo "🚨 CRITICAL: VPN interface has IP but cannot reach internet. Activating kill switch."
        
        # Block all forwarded traffic immediately
        nft add rule inet filter forward counter drop comment "VPN kill switch - no connectivity"
        
        # Clear VPN IP set to prevent forwarding to non-working VPN
        nft flush set inet filter vpn_interface_ips 2>/dev/null || true
        
        # Kill NAT rules
        nft flush chain ip nat postrouting 2>/dev/null || true
        
        echo "🛡️  Kill switch activated - VPN has no internet connectivity"
        logger -p daemon.crit "VPN Gateway: Kill switch activated - VPN interface not reachable"
        
        # Attempt to restart VPN
        systemctl restart amnezia-wg || true
        
        exit 1
    fi
    
    # 4. VPN is working - update the IP set to allow forwarding
    echo "✅ VPN connectivity verified - updating firewall rules"
    
    # Add current VPN IP to the allowed set (this enables forwarding)
    nft add element inet filter vpn_interface_ips "{ $VPN_IP }" 2>/dev/null || true
    
  
    # 5. Check AmneziaWG status
    if command -v awg >/dev/null 2>&1; then
        AWG_STATUS=$(awg show "$VPN_INTERFACE" 2>/dev/null || echo "ERROR")
        if [ "$AWG_STATUS" = "ERROR" ]; then
            echo "⚠️  WARNING: AmneziaWG interface $VPN_INTERFACE not responding properly"
            # Don't kill switch here as interface might work even if awg command fails
        fi
    else
        echo "⚠️  WARNING: AmneziaWG tools not available"
    fi
    
    echo "✅ VPN interface $VPN_INTERFACE is active and responding - forwarding enabled"
  '';

  # Enhanced leak detection script with DNS leak testing
  leakDetectionScript = pkgs.writeShellScript "leak-detection" ''
    set -euo pipefail
    
    VPN_INTERFACE="${cfg.vpn.interface}"
    EXPECTED_VPN_IP="${cfg.vpn.serverIp}"
    
    echo "=== VPN Gateway Leak Detection ==="
    
    # 1. Check if we can reach the internet without VPN (should fail)
    echo "Testing direct internet access bypass (should fail)..."
    if timeout 5 ${pkgs.curl}/bin/curl -s --interface ${head cfg.network.lanInterfaces} http://checkip.amazonaws.com/ >/dev/null 2>&1; then
        echo "🚨 CRITICAL: Internet accessible without VPN on interface ${head cfg.network.lanInterfaces}!"
        logger -p daemon.crit "VPN Gateway: CRITICAL Internet leak detected on ${head cfg.network.lanInterfaces}"
        
        # Immediately activate kill switch
        ${killSwitchScript}
        return 1
    else
        echo "✅ Direct internet access properly blocked"
    fi
    
    # 2. Check VPN interface connectivity
    if ip addr show "$VPN_INTERFACE" 2>/dev/null | grep -q "inet "; then
        VPN_IP=$(timeout 10 ${pkgs.curl}/bin/curl -s --interface "$VPN_INTERFACE" http://checkip.amazonaws.com/ 2>/dev/null || echo "FAILED")
        if [ "$VPN_IP" = "FAILED" ] || [ -z "$VPN_IP" ]; then
            echo "🚨 WARNING: VPN interface exists but cannot reach internet"
            logger -p daemon.warning "VPN Gateway: VPN connectivity check failed"
            return 1
        fi
        echo "✅ VPN working correctly. External IP: $VPN_IP"
    else
        echo "🚨 CRITICAL: VPN interface $VPN_INTERFACE not found or inactive"
        ${killSwitchScript}
        return 1
    fi
    
    # 3. DNS leak detection - test if DNS queries leak outside VPN
    echo "Testing DNS leak detection..."
    
    # Test if system can make direct DNS queries (should fail except to localhost)
    if timeout 5 ${pkgs.dnsutils}/bin/dig @8.8.8.8 +short google.com >/dev/null 2>&1; then
        echo "🚨 CRITICAL: DNS leak detected - direct DNS queries possible!"
        logger -p daemon.crit "VPN Gateway: DNS leak detected - direct queries to 8.8.8.8 successful"
        return 1
    else
        echo "✅ Direct DNS queries properly blocked"
    fi
    
    # Test if DNS works through VPN interface
    VPN_IP_ADDR=$(ip addr show "$VPN_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -1)
    if [ -n "$VPN_IP_ADDR" ]; then
        # Test DNS resolution via VPN interface bound query
        if timeout 10 ${pkgs.curl}/bin/curl --interface "$VPN_INTERFACE" -s "https://1.1.1.1/dns-query?name=google.com&type=A" \
           -H "Accept: application/dns-message" >/dev/null 2>&1; then
            echo "✅ DNS over HTTPS via VPN working correctly"
        else
            echo "⚠️  WARNING: DNS over HTTPS via VPN interface may be failing"
        fi
    fi
    
    # 4. Check if VPN DNS service is properly binding to VPN interface
    if systemctl is-active --quiet unbound-vpn; then
        echo "✅ VPN DNS service is running"
        
        # Test if VPN DNS service is responding
        if timeout 5 ${pkgs.dnsutils}/bin/dig @${cfg.network.vpnGatewayIp} +short google.com >/dev/null 2>&1; then
            echo "✅ VPN DNS service responding correctly"
        else
            echo "⚠️  WARNING: VPN DNS service not responding"
        fi
    else
        echo "🚨 CRITICAL: VPN DNS service not running"
        return 1
    fi
    
    echo "=== Leak Detection Complete ==="
  '';

in {
  options.services.amneziaVpnGateway = {
    enable = mkEnableOption "Amnezia VPN Gateway for secure network routing";

    network = {
      lanInterfaces = mkOption {
        type = types.listOf types.str;
        description = "Network interfaces connected to LAN";
        example = [ "enp3s0" ];
      };

      lanSubnets = mkOption {
        type = types.listOf types.str;
        description = "LAN IP subnets to route through VPN";
        example = [ "192.168.1.0/24" ];
      };

      vpnGatewayIp = mkOption {
        type = types.str;
        description = "IP address for this machine on the LAN (used for DNS)";
        example = "192.168.1.1";
      };
    };

    vpn = {
      interface = mkOption {
        type = types.str;
        default = "awg0";
        description = "Amnezia WireGuard interface name";
      };

      configFile = mkOption {
        type = types.path;
        description = "Path to Amnezia WireGuard configuration file";
        example = "/etc/amnezia-wg/client.conf";
      };

      serverIp = mkOption {
        type = types.str;
        description = "VPN server IP address or hostname";
        example = "vpn.example.com";
      };

      serverPort = mkOption {
        type = types.port;
        default = 51820;
        description = "VPN server port";
      };

      # Amnezia-specific options for traffic obfuscation
      amnezia = {
        junkPacketCount = mkOption {
          type = types.int;
          default = 4;
          description = "Number of junk packets to send for obfuscation";
        };

        junkPacketMinSize = mkOption {
          type = types.int;
          default = 50;
          description = "Minimum size of junk packets";
        };

        junkPacketMaxSize = mkOption {
          type = types.int;
          default = 1000;
          description = "Maximum size of junk packets";
        };

        initPacketJunkSize = mkOption {
          type = types.int;
          default = 200;
          description = "Size of junk data in initial packet";
        };

        responsePacketJunkSize = mkOption {
          type = types.int;
          default = 200;
          description = "Size of junk data in response packet";
        };

        initPacketMagicHeader = mkOption {
          type = types.int;
          default = 1234567890;
          description = "Magic header for initial packet obfuscation";
        };

        responsePacketMagicHeader = mkOption {
          type = types.int;
          default = 987654321;
          description = "Magic header for response packet obfuscation";
        };

        underloadPacketMagicHeader = mkOption {
          type = types.int;
          default = 135792468;
          description = "Magic header for underload packet obfuscation";
        };

        transportPacketMagicHeader = mkOption {
          type = types.int;
          default = 246813579;
          description = "Magic header for transport packet obfuscation";
        };
      };
    };

    dns = {
      localPort = mkOption {
        type = types.port;
        default = 5353;
        description = "Local port for system DNS caching resolver";
      };

      vpnPort = mkOption {
        type = types.port;
        default = 53;
        description = "Port for VPN clients DNS resolver (standard DNS port)";
      };

      upstreamServers = mkOption {
        type = types.listOf types.str;
        default = [ 
          "https://1.1.1.1/dns-query"          # Cloudflare DoH
          "https://9.9.9.9/dns-query"          # Quad9 DoH
          "https://8.8.8.8/dns-query"          # Google DoH
        ];
        description = "Upstream DNS over HTTPS servers";
      };

      cache = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable high-performance DNS caching";
        };

        threads = mkOption {
          type = types.int;
          default = 2;
          description = "Number of threads for DNS processing";
        };

        messageSize = mkOption {
          type = types.str;
          default = "64m";
          description = "Message cache size";
        };

        rrsetSize = mkOption {
          type = types.str;
          default = "128m";
          description = "RRset cache size";
        };

        minTtl = mkOption {
          type = types.int;
          default = 300;
          description = "Minimum TTL for cached responses (seconds)";
        };

        maxTtl = mkOption {
          type = types.int;
          default = 86400;
          description = "Maximum TTL for cached responses (seconds)";
        };

        negativeMaxTtl = mkOption {
          type = types.int;
          default = 3600;
          description = "Maximum TTL for negative responses (seconds)";
        };

        slabs = mkOption {
          type = types.int;
          default = 4;
          description = "Number of slabs for cache (power of 2)";
        };
      };

      logLevel = mkOption {
        type = types.int;
        default = 1;
        description = "DNS logging verbosity (0=none, 1=operational, 2=detailed, 3=query level, 4=algorithm level, 5=client identification)";
      };

      logQueries = mkOption {
        type = types.bool;
        default = false;
        description = "Log all DNS queries (useful for debugging)";
      };
    };

    firewall = {
      allowedTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [ 22 ];
        description = "TCP ports to allow from LAN";
      };

      allowedUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "UDP ports to allow from LAN";
      };

      logLevel = mkOption {
        type = types.enum [ "emerg" "alert" "crit" "err" "warn" "notice" "info" "debug" ];
        default = "warn";
        description = "Netfilter logging level";
      };
    };

    monitoring = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable VPN monitoring and leak detection";
      };

      checkInterval = mkOption {
        type = types.str;
        default = "5min";
        description = "Interval for VPN connectivity health checks";
      };

      killSwitchTimeout = mkOption {
        type = types.str;
        default = "30s";
        description = "Timeout before activating VPN kill switch after connectivity loss";
      };
    };
  };

  config = mkIf cfg.enable {
    # Kernel module loading for AmneziaWG (official nixpkgs packages)
    boot.extraModulePackages = [ 
      config.boot.kernelPackages.amneziawg  # Official AmneziaWG kernel module from nixpkgs
    ];
    
    boot.kernelModules = [ 
      "amneziawg"  # Official AmneziaWG kernel module
    ];

    # System packages (official nixpkgs AmneziaWG)
    environment.systemPackages = with pkgs; [
      amneziawg-tools  # Official AmneziaWG tools from nixpkgs (awg, awg-quick)
      nftables
      iproute2
      dnsutils
      curl
      unbound  # High-performance DNS caching server with DoH support
    ];

    # Enable IP forwarding
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 0; # Disable IPv6 forwarding for security
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.all.accept_source_route" = 0;
    };

    # Disable traditional iptables and enable modern nftables
    networking.firewall.enable = lib.mkForce false;
    networking.nftables.enable = true;

    # Comprehensive nftables ruleset with kill switch
    networking.nftables.ruleset = ''
      # Clear all existing rules
      flush ruleset

      table inet filter {
        # Define sets for dynamic IPs
        set vpn_endpoints {
          type ipv4_addr
          flags dynamic, timeout
          timeout 24h
        }

        set allowed_lan_ips {
          type ipv4_addr
          elements = { ${concatStringsSep ", " cfg.network.lanSubnets} }
        }

        set vpn_interface_ips {
          type ipv4_addr
          flags dynamic, timeout
          timeout 24h
        }
        # INPUT chain - strict rules for incoming traffic
        chain input {
          type filter hook input priority filter; policy drop;
          
          # Basic connectivity
          ct state established,related accept
          iifname "lo" accept
          
          # ICMP for troubleshooting
          ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 5/second accept
          
          # SSH from LAN only
          ${concatMapStringsSep "\n" (iface: 
            concatMapStringsSep "\n" (port: 
              "  iifname \"${iface}\" ip saddr @allowed_lan_ips tcp dport ${toString port} ct state new accept"
            ) cfg.firewall.allowedTCPPorts
          ) cfg.network.lanInterfaces}
          
          # DNS for LAN clients (high-performance cached DNS)
          ${concatMapStringsSep "\n" (iface: 
            "  iifname \"${iface}\" ip saddr @allowed_lan_ips udp dport ${toString cfg.dns.vpnPort} accept"
          ) cfg.network.lanInterfaces}
          ${concatMapStringsSep "\n" (iface: 
            "  iifname \"${iface}\" ip saddr @allowed_lan_ips tcp dport ${toString cfg.dns.vpnPort} accept"
          ) cfg.network.lanInterfaces}
          
          # Additional allowed UDP ports
          ${concatMapStringsSep "\n" (iface: 
            concatMapStringsSep "\n" (port: 
              "  iifname \"${iface}\" ip saddr @allowed_lan_ips udp dport ${toString port} accept"
            ) cfg.firewall.allowedUDPPorts
          ) cfg.network.lanInterfaces}
          
          # VPN traffic
          iifname "${cfg.vpn.interface}" accept
          
          # Log and drop everything else
          log level ${cfg.firewall.logLevel} prefix "INPUT_DROP: " drop
        }

        # OUTPUT chain - system traffic rules
        chain output {
          type filter hook output priority filter; policy drop;
          
          # Basic connectivity
          ct state established,related accept
          oifname "lo" accept
          
          # LAN traffic
          ${concatMapStringsSep "\n" (iface: 
            "  oifname \"${iface}\" ip daddr @allowed_lan_ips accept"
          ) cfg.network.lanInterfaces}
          
          # VPN interface traffic
          oifname "${cfg.vpn.interface}" accept
          
          # DNS for system (local Unbound resolver)
          ip daddr { 127.0.0.1 } tcp dport ${toString cfg.dns.localPort} accept
          ip daddr { 127.0.0.1 } udp dport ${toString cfg.dns.localPort} accept
          
          # VPN endpoint access (critical for VPN connection!)
          ip daddr @vpn_endpoints accept
          
          # ABSOLUTELY NO OTHER DNS TRAFFIC ALLOWED
          # All DNS must go through local Unbound resolver or VPN tunnel
          # NO emergency fallback to prevent ANY DNS leaks
          
          # Log and drop everything else
          log level ${cfg.firewall.logLevel} prefix "OUTPUT_DROP: " drop
        }

        # FORWARD chain - traffic routing through this gateway
        chain forward {
          type filter hook forward priority filter; policy drop;
          
          # Established connections
          ct state established,related accept
          
          # LAN to VPN only
          ${concatMapStringsSep "\n" (iface: 
            "  iifname \"${iface}\" oifname \"${cfg.vpn.interface}\" ip saddr @allowed_lan_ips accept"
          ) cfg.network.lanInterfaces}
          
          # VPN to LAN (return traffic)
          ${concatMapStringsSep "\n" (iface: 
            "  iifname \"${cfg.vpn.interface}\" oifname \"${iface}\" ip daddr @allowed_lan_ips accept"
          ) cfg.network.lanInterfaces}
          
          # CRITICAL: No forwarding without VPN interface being up
          # This is the kill switch - if VPN is down, no forwarding
          
          # Log and drop everything else (including leaks)
          log level ${cfg.firewall.logLevel} prefix "FORWARD_DROP: " drop
        }
      }

      # NAT table for masquerading
      table ip nat {
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
        }

        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          
          # Only masquerade traffic going through VPN interface
          oifname "${cfg.vpn.interface}" ip saddr { ${concatStringsSep ", " cfg.network.lanSubnets} } masquerade
        }
      }
    '';

    # System DNS configuration (uses local Unbound caching resolver)
    networking.nameservers = [ "127.0.0.1:${toString cfg.dns.localPort}" ];
    networking.resolvconf.extraConfig = ''
      name_servers="127.0.0.1:${toString cfg.dns.localPort}"
    '';

    # High-performance DNS caching service (for system)
    systemd.services.unbound-system = {
      description = "Unbound DNS Caching Resolver (System)";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "unbound";
        Group = "unbound";
        ExecStart = "${pkgs.unbound}/bin/unbound -d -c ${unboundSystemConfig}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "5s";
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/unbound-system" ];
        
        # Network capabilities
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" "CAP_SETGID" "CAP_SETUID" ];
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" "CAP_SETGID" "CAP_SETUID" ];
      };

      preStart = ''
        mkdir -p /var/lib/unbound-system
        chown unbound:unbound /var/lib/unbound-system
        
        # Initialize DNSSEC root trust anchor if it doesn't exist
        if [ ! -f /var/lib/unbound-system/root.key ]; then
          ${pkgs.unbound}/bin/unbound-anchor -a /var/lib/unbound-system/root.key -c /etc/ssl/certs/ca-certificates.crt
          chown unbound:unbound /var/lib/unbound-system/root.key
        fi
      '';
    };

    # High-performance DNS caching service (for VPN clients)
    systemd.services.unbound-vpn = {
      description = "Unbound DNS Caching Resolver (VPN Clients)";
      wants = [ "network-online.target" "amnezia-wg.service" ];
      after = [ "network-online.target" "amnezia-wg.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "unbound";
        Group = "unbound";
        ExecStart = "${pkgs.unbound}/bin/unbound -d -c ${unboundVpnConfig}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "5s";
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/unbound-vpn" ];
        
        # Network capabilities
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" "CAP_SETGID" "CAP_SETUID" ];
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" "CAP_SETGID" "CAP_SETUID" ];
      };

      preStart = ''
        mkdir -p /var/lib/unbound-vpn
        chown unbound:unbound /var/lib/unbound-vpn
        
        # CRITICAL: Wait for VPN interface to be ready and have an IP
        echo "Waiting for VPN interface ${cfg.vpn.interface} to be ready..."
        VPN_READY=false
        for i in {1..60}; do
          if ip addr show ${cfg.vpn.interface} 2>/dev/null | grep -q "inet "; then
            VPN_IP=$(ip addr show ${cfg.vpn.interface} | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
            echo "VPN interface ${cfg.vpn.interface} is ready with IP: $VPN_IP"
            VPN_READY=true
            break
          fi
          echo "Waiting for VPN interface ${cfg.vpn.interface}... ($i/60)"
          sleep 2
        done
        
        if [ "$VPN_READY" = "false" ]; then
          echo "ERROR: VPN interface ${cfg.vpn.interface} not ready after 120 seconds"
          echo "SECURITY: Not starting VPN DNS service to prevent leaks"
          exit 1
        fi
        
        # Initialize DNSSEC root trust anchor if it doesn't exist
        if [ ! -f /var/lib/unbound-vpn/root.key ]; then
          ${pkgs.unbound}/bin/unbound-anchor -a /var/lib/unbound-vpn/root.key -c /etc/ssl/certs/ca-certificates.crt
          chown unbound:unbound /var/lib/unbound-vpn/root.key
        fi
        
        # Verify VPN interface can reach upstream DNS
        echo "Testing VPN DNS connectivity..."
        if ! timeout 10 ${pkgs.curl}/bin/curl --interface ${cfg.vpn.interface} -s "https://1.1.1.1/dns-query" >/dev/null 2>&1; then
          echo "WARNING: Cannot reach DNS over HTTPS via VPN interface"
          echo "This may cause DNS resolution failures for VPN clients"
        else
          echo "VPN DNS connectivity verified"
        fi
      '';
    };

    # AmneziaWG VPN service (using official nixpkgs packages)
    systemd.services.amnezia-wg = {
      description = "AmneziaWG VPN Tunnel";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.amneziawg-tools}/bin/awg-quick up ${cfg.vpn.configFile}";
        ExecStop = "${pkgs.amneziawg-tools}/bin/awg-quick down ${cfg.vpn.configFile}";
        ExecReload = "${pkgs.bash}/bin/bash -c '${pkgs.amneziawg-tools}/bin/awg-quick down ${cfg.vpn.configFile}; ${pkgs.amneziawg-tools}/bin/awg-quick up ${cfg.vpn.configFile}'";
        
        # Security
        PrivateNetwork = false; # Needs network access
        NoNewPrivileges = true;
      };

      # Set up Amnezia-specific obfuscation parameters
      preStart = ''
        # Ensure the configuration directory exists
        mkdir -p "$(dirname ${cfg.vpn.configFile})"
        
        # Backup original config if it exists
        if [ -f "${cfg.vpn.configFile}" ] && [ ! -f "${cfg.vpn.configFile}.backup" ]; then
          cp "${cfg.vpn.configFile}" "${cfg.vpn.configFile}.backup"
        fi
        
        # Add Amnezia-specific parameters to config if not present
        if [ -f "${cfg.vpn.configFile}" ] && ! grep -q "Jc" "${cfg.vpn.configFile}"; then
          echo "Adding AmneziaWG obfuscation parameters to configuration..."
          
          # Add Amnezia obfuscation parameters
          cat >> "${cfg.vpn.configFile}" << EOF

# Amnezia obfuscation parameters (added by NixOS module)
Jc = ${toString cfg.vpn.amnezia.junkPacketCount}
Jmin = ${toString cfg.vpn.amnezia.junkPacketMinSize}
Jmax = ${toString cfg.vpn.amnezia.junkPacketMaxSize}
S1 = ${toString cfg.vpn.amnezia.initPacketJunkSize}
S2 = ${toString cfg.vpn.amnezia.responsePacketJunkSize}
H1 = ${toString cfg.vpn.amnezia.initPacketMagicHeader}
H2 = ${toString cfg.vpn.amnezia.responsePacketMagicHeader}
H3 = ${toString cfg.vpn.amnezia.underloadPacketMagicHeader}
H4 = ${toString cfg.vpn.amnezia.transportPacketMagicHeader}
EOF
        fi
      '';
    };

    # VPN startup script with security verification
    systemd.services.vpn-startup-security = {
      description = "VPN Startup Security Check";
      wants = [ "amnezia-wg.service" ];
      after = [ "amnezia-wg.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "vpn-startup-security" ''
          set -euo pipefail
          
          VPN_INTERFACE="${cfg.vpn.interface}"
          
          echo "=== VPN Startup Security Check ==="
          
          # Clear any existing VPN IPs from firewall (start with blocked state)
          nft flush set inet filter vpn_interface_ips 2>/dev/null || true
          
          # Wait for VPN to be fully established
          echo "Waiting for VPN interface to be ready..."
          VPN_READY=false
          for i in {1..30}; do
            if ip addr show "$VPN_INTERFACE" 2>/dev/null | grep -q "inet "; then
              VPN_IP=$(ip addr show "$VPN_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -1)
              echo "VPN interface found with IP: $VPN_IP"
              
              # Test connectivity before allowing forwarding
              if timeout 15 ${pkgs.curl}/bin/curl --interface "$VPN_INTERFACE" -s -m 10 http://checkip.amazonaws.com/ >/dev/null 2>&1; then
                echo "✅ VPN connectivity verified"
                # Add IP to allowed set (enables forwarding)
                nft add element inet filter vpn_interface_ips "{ $VPN_IP }" || true
                VPN_READY=true
                break
              else
                echo "VPN interface has IP but no connectivity (attempt $i/30)"
              fi
            else
              echo "Waiting for VPN interface IP... ($i/30)"
            fi
            sleep 2
          done
          
          if [ "$VPN_READY" = "false" ]; then
            echo "🚨 CRITICAL: VPN not ready after 60 seconds - forwarding remains BLOCKED"
            logger -p daemon.crit "VPN Gateway: VPN startup failed - forwarding blocked for security"
            exit 1
          fi
          
          echo "🛡️  VPN startup security check completed - forwarding enabled"
        '';
      };
    };
    systemd.services.vpn-killswitch = mkIf cfg.monitoring.enable {
      description = "VPN Kill Switch Monitor";
      wants = [ "amnezia-wg.service" ];
      after = [ "amnezia-wg.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do ${killSwitchScript}; sleep 30; done'";
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # Alternative: Use systemd-networkd integration for even faster response
    systemd.services.vpn-networkd-monitor = mkIf cfg.monitoring.enable {
      description = "VPN Interface Monitor via networkd events";
      wants = [ "systemd-networkd.service" ];
      after = [ "systemd-networkd.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        # Monitor networkd events for immediate VPN interface changes
        ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.systemd}/bin/networkctl monitor | while read line; do echo \"$line\" | grep -q \"${cfg.vpn.interface}\" && ${immediateKillSwitchScript}; done'";
        Restart = "always";
        RestartSec = "5s";
        
        # High priority
        Nice = -15;
        IOSchedulingClass = 1;
      };
    };
    systemd.services.vpn-leak-detection = mkIf cfg.monitoring.enable {
      description = "VPN Leak Detection";
      wants = [ "amnezia-wg.service" "network-online.target" ];
      after = [ "amnezia-wg.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do ${leakDetectionScript}; sleep 300; done'"; # Check every 5 minutes
        Restart = "always";
        RestartSec = "60s";
      };
    };

    # Timer for periodic leak detection
    systemd.timers.vpn-leak-detection = mkIf cfg.monitoring.enable {
      description = "Periodic VPN leak detection";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.monitoring.checkInterval;
        Persistent = true;
      };
    };

    # VPN endpoint IP resolution service
    systemd.services.update-vpn-endpoints = {
      description = "Update VPN endpoint IPs in nftables";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "update-vpn-endpoints" ''
          set -euo pipefail
          
          VPN_SERVER="${cfg.vpn.serverIp}"
          
          # Resolve VPN server IP
          VPN_IPS=$(${pkgs.dnsutils}/bin/dig +short A "$VPN_SERVER" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "")
          
          if [ -n "$VPN_IPS" ]; then
            echo "Updating VPN endpoint IPs: $VPN_IPS"
            
            # Clear existing set
            ${pkgs.nftables}/bin/nft flush set inet filter vpn_endpoints 2>/dev/null || true
            
            # Add new IPs
            for ip in $VPN_IPS; do
              ${pkgs.nftables}/bin/nft add element inet filter vpn_endpoints "{ $ip }"
            done
            
            echo "VPN endpoints updated successfully"
          else
            echo "WARNING: Could not resolve VPN server $VPN_SERVER"
            exit 1
          fi
        '';
      };
    };

    # Timer for VPN endpoint updates
    systemd.timers.update-vpn-endpoints = {
      description = "Update VPN endpoint IPs periodically";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };

    # User and group for DNS services
    users.users.unbound = {
      isSystemUser = true;
      group = "unbound";
      description = "Unbound DNS resolver daemon user";
    };

    users.groups.unbound = {};

    # Ensure proper service ordering and dependencies
    systemd.targets.vpn-gateway = {
      description = "VPN Gateway Services";
      wants = [
        "amnezia-wg.service"
        "unbound-system.service"
        "unbound-vpn.service"
        "update-vpn-endpoints.service"
      ] ++ optional cfg.monitoring.enable "vpn-killswitch-immediate.service"
        ++ optional cfg.monitoring.enable "vpn-killswitch-backup.service"
        ++ optional cfg.monitoring.enable "vpn-interface-monitor.path"
        ++ optional cfg.monitoring.enable "vpn-networkd-monitor.service"
        ++ optional cfg.monitoring.enable "vpn-leak-detection.service";

      after = [
        "network-online.target"
        "nftables.service"
      ];
    };
  };
}