# Example configuration for Amnezia VPN Gateway
# This file shows various configuration scenarios for the module

{
  # Basic home network VPN gateway setup
  basic-home-gateway = {
    services.amneziaVpnGateway = {
      enable = true;

      network = {
        lanInterfaces = [ "enp3s0" ];           # Your main ethernet interface
        lanSubnets = [ "192.168.1.0/24" ];      # Your home network subnet
        vpnGatewayIp = "192.168.1.1";           # This machine's IP on LAN
      };

      vpn = {
        interface = "awg0";                      # Amnezia WireGuard interface
        configFile = "/etc/amnezia-wg/client.conf";
        serverIp = "vpn.example.com";           # Your VPN provider's server
        serverPort = 51820;
      };

      dns = {
        localPort = 5353;                       # Local DNS over HTTPS port
        upstreamServers = [ "1.1.1.1" "9.9.9.9" ]; # Emergency fallback DNS
      };

      firewall = {
        allowedTCPPorts = [ 22 ];               # SSH access from LAN
        logLevel = "warn";                      # Firewall logging level
      };

      monitoring = {
        enable = true;                          # Enable VPN monitoring
        checkInterval = "5min";                 # Health check frequency
        killSwitchTimeout = 30;                 # Kill switch delay (seconds)
      };
    };
  };

  # Advanced setup with multiple interfaces and custom obfuscation
  advanced-multi-interface = {
    services.amneziaVpnGateway = {
      enable = true;

      network = {
        # Multiple network interfaces (ethernet + wifi)
        lanInterfaces = [ "enp3s0" "wlp2s0" ];
        lanSubnets = [ 
          "192.168.1.0/24"    # Main LAN
          "192.168.2.0/24"    # Guest network
          "10.0.0.0/24"       # IoT network
        ];
        vpnGatewayIp = "192.168.1.1";
      };

      vpn = {
        interface = "awg0";
        configFile = "/etc/amnezia-wg/client.conf";
        serverIp = "secure-vpn.example.org";
        serverPort = 443;                       # Use HTTPS port for stealth

        # Custom Amnezia obfuscation parameters for maximum stealth
        amnezia = {
          junkPacketCount = 8;                  # More junk packets
          junkPacketMinSize = 20;               # Smaller minimum size
          junkPacketMaxSize = 1400;             # Larger maximum size
          initPacketJunkSize = 400;             # Larger initial packet
          responsePacketJunkSize = 400;         # Larger response packet
          
          # Custom magic headers (change these for your setup!)
          initPacketMagicHeader = 1122334455;
          responsePacketMagicHeader = 5544332211;
          underloadPacketMagicHeader = 9988776655;
          transportPacketMagicHeader = 5566778899;
        };
      };

      dns = {
        localPort = 5353;
        upstreamServers = [ 
          "1.1.1.1"           # Cloudflare
          "9.9.9.9"           # Quad9
          "8.8.8.8"           # Google (backup)
        ];
      };

      firewall = {
        allowedTCPPorts = [ 
          22                  # SSH
          80                  # HTTP (for local services)
          443                 # HTTPS (for local services)
          8080                # Alternative HTTP
        ];
        allowedUDPPorts = [
          53                  # DNS (if needed)
          67                  # DHCP server (if running)
        ];
        logLevel = "info";    # More verbose logging
      };

      monitoring = {
        enable = true;
        checkInterval = "2min";                 # More frequent checks
        killSwitchTimeout = 15;                 # Faster kill switch
      };
    };
  };

  # High-security paranoid setup
  paranoid-security = {
    services.amneziaVpnGateway = {
      enable = true;

      network = {
        lanInterfaces = [ "enp3s0" ];
        lanSubnets = [ "192.168.1.0/24" ];
        vpnGatewayIp = "192.168.1.1";
      };

      vpn = {
        interface = "awg0";
        configFile = "/etc/amnezia-wg/client.conf";
        serverIp = "stealth-vpn.example.net";
        serverPort = 853;                       # DNS over TLS port for stealth

        # Maximum obfuscation settings
        amnezia = {
          junkPacketCount = 12;                 # Maximum junk packets
          junkPacketMinSize = 10;               # Very small minimum
          junkPacketMaxSize = 1500;             # Maximum MTU size
          initPacketJunkSize = 600;             # Large initial packet
          responsePacketJunkSize = 600;         # Large response packet
          
          # Randomized magic headers (use your own values!)
          initPacketMagicHeader = 2147483647;
          responsePacketMagicHeader = 1073741823;
          underloadPacketMagicHeader = 536870911;
          transportPacketMagicHeader = 268435455;
        };
      };

      dns = {
        localPort = 5353;
        # Only privacy-focused DNS servers
        upstreamServers = [ 
          "9.9.9.9"           # Quad9 (privacy-focused)
          "149.112.112.112"   # Quad9 alternative
        ];
      };

      firewall = {
        allowedTCPPorts = [ 22 ];               # Only SSH
        allowedUDPPorts = [ ];                  # No UDP ports
        logLevel = "debug";                     # Maximum logging
      };

      monitoring = {
        enable = true;
        checkInterval = "1min";                 # Very frequent checks
        killSwitchTimeout = 5;                  # Immediate kill switch
      };
    };
  };

  # Small office/business setup
  business-setup = {
    services.amneziaVpnGateway = {
      enable = true;

      network = {
        lanInterfaces = [ "enp1s0" "enp2s0" ];  # Bonded interfaces
        lanSubnets = [ 
          "10.0.1.0/24"       # Employee network
          "10.0.2.0/24"       # Server network  
          "10.0.3.0/24"       # Guest network
        ];
        vpnGatewayIp = "10.0.1.1";
      };

      vpn = {
        interface = "awg0";
        configFile = "/etc/amnezia-wg/business.conf";
        serverIp = "business-vpn.company.com";
        serverPort = 993;                       # IMAPS port for stealth

        amnezia = {
          junkPacketCount = 6;                  # Balanced performance/security
          junkPacketMinSize = 40;
          junkPacketMaxSize = 1200;
          initPacketJunkSize = 250;
          responsePacketJunkSize = 250;
          initPacketMagicHeader = 1357924680;
          responsePacketMagicHeader = 2468013579;
          underloadPacketMagicHeader = 3691470258;
          transportPacketMagicHeader = 4702581369;
        };
      };

      dns = {
        localPort = 5353;
        upstreamServers = [ 
          "1.1.1.1"           # Fast primary
          "1.0.0.1"           # Fast secondary
          "9.9.9.9"           # Privacy backup
        ];
      };

      firewall = {
        allowedTCPPorts = [ 
          22                  # SSH
          53                  # DNS
          80                  # HTTP
          443                 # HTTPS
          993                 # IMAPS
          995                 # POP3S
          3389                # RDP (if needed)
        ];
        allowedUDPPorts = [
          53                  # DNS
          67                  # DHCP
          123                 # NTP
        ];
        logLevel = "warn";    # Balanced logging
      };

      monitoring = {
        enable = true;
        checkInterval = "3min";                 # Business-appropriate interval
        killSwitchTimeout = 20;                 # Balanced timeout
      };
    };

    # Additional business configurations
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;        # Key-only access
        PermitRootLogin = "no";               # No root SSH
      };
    };

    # Network Time Protocol for accurate logging
    services.ntp.enable = true;

    # System monitoring and logging
    services.journald.extraConfig = ''
      SystemMaxUse=1G
      MaxRetentionSec=1month
    '';
  };

  # Development/testing setup with relaxed security
  development-setup = {
    services.amneziaVpnGateway = {
      enable = true;

      network = {
        lanInterfaces = [ "enp0s3" ];           # VirtualBox/VMware interface
        lanSubnets = [ "192.168.56.0/24" ];     # Host-only network
        vpnGatewayIp = "192.168.56.10";
      };

      vpn = {
        interface = "awg0";
        configFile = "/etc/amnezia-wg/dev.conf";
        serverIp = "dev-vpn.test.local";
        serverPort = 51820;

        # Minimal obfuscation for testing
        amnezia = {
          junkPacketCount = 2;                  # Minimal junk
          junkPacketMinSize = 50;
          junkPacketMaxSize = 500;
          initPacketJunkSize = 100;
          responsePacketJunkSize = 100;
          initPacketMagicHeader = 1234567890;
          responsePacketMagicHeader = 987654321;
          underloadPacketMagicHeader = 1122334455;
          transportPacketMagicHeader = 5544332211;
        };
      };

      dns = {
        localPort = 5353;
        upstreamServers = [ "8.8.8.8" "8.8.4.4" ]; # Google DNS for testing
      };

      firewall = {
        allowedTCPPorts = [ 
          22                  # SSH
          80                  # HTTP
          443                 # HTTPS
          3000                # Development servers
          8000                # Alternative dev port
          8080                # Alternative dev port
          9000                # Another dev port
        ];
        allowedUDPPorts = [ 53 67 ];
        logLevel = "debug";   # Maximum logging for debugging
      };

      monitoring = {
        enable = true;
        checkInterval = "10min";                # Less frequent for dev
        killSwitchTimeout = 60;                 # Longer timeout for dev
      };
    };

    # Development tools
    environment.systemPackages = with pkgs; [
      tcpdump                                  # Network debugging
      wireshark-cli                           # Packet analysis
      netcat                                  # Network testing
      nmap                                    # Network scanning
      iperf3                                  # Bandwidth testing
    ];
  };
}