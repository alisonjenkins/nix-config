# Amnezia VPN Gateway Module

A comprehensive NixOS module for creating a secure VPN gateway using Amnezia WireGuard that routes your home network traffic through an obfuscated VPN connection while preventing any DNS or IP leaks.

## Features

### 🔒 **Security & Privacy**
- **Amnezia WireGuard**: Traffic obfuscation to bypass ISP and network administrator detection
- **Kill Switch**: Automatic traffic blocking if VPN connection drops
- **DNS over HTTPS (DoH)**: All DNS queries encrypted and routed through VPN
- **Leak Prevention**: Comprehensive leak detection and monitoring
- **Zero-Log DNS**: Uses privacy-focused DNS servers with DNSSEC validation

### 🌐 **Network Architecture**
- **Dual DNS Setup**: Separate DNS resolvers for system and VPN-routed traffic
- **Modern Netfilter**: Uses nftables instead of legacy iptables
- **IP Forwarding**: Secure routing of LAN traffic through VPN tunnel
- **Dynamic IP Resolution**: Automatic updates for VPN server endpoints

### 📊 **Monitoring & Reliability**
- **Real-time Monitoring**: Continuous VPN connectivity checks
- **Automatic Recovery**: Service restart and reconnection on failures
- **Comprehensive Logging**: Detailed logs for troubleshooting
- **Health Checks**: Regular verification of VPN and DNS functionality

## How It Works

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   LAN Clients   │───▶│  VPN Gateway    │───▶│   Internet      │
│ (192.168.1.x)   │    │ (This Machine)  │    │ (via VPN only)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │ Amnezia WG VPN  │
                       │ (Obfuscated)    │
                       └─────────────────┘
```

### Traffic Flow
1. **LAN clients** send traffic to this gateway machine
2. **nftables firewall** ensures traffic can only exit through VPN interface
3. **Amnezia WireGuard** obfuscates traffic to prevent VPN detection
4. **DNS over HTTPS** handles all DNS queries securely through VPN
5. **Kill switch** blocks all traffic if VPN connection fails

## Configuration

### Basic Example

```nix
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
    serverIp = "vpn.example.com";
    serverPort = 51820;
  };

  dns = {
    localPort = 5353;
    upstreamServers = [ "1.1.1.1" "9.9.9.9" ];
  };

  firewall = {
    allowedTCPPorts = [ 22 ];  # SSH access
    logLevel = "warn";
  };

  monitoring = {
    enable = true;
    checkInterval = "5min";
    killSwitchTimeout = 30;
  };
};
```

### Advanced Configuration with Custom Obfuscation

```nix
services.amneziaVpnGateway = {
  enable = true;

  network = {
    lanInterfaces = [ "enp3s0" "wlp2s0" ];
    lanSubnets = [ "192.168.1.0/24" "192.168.2.0/24" ];
    vpnGatewayIp = "192.168.1.1";
  };

  vpn = {
    interface = "awg0";
    configFile = "/etc/amnezia-wg/client.conf";
    serverIp = "vpn.example.com";
    serverPort = 51820;

    # Amnezia-specific obfuscation settings
    amnezia = {
      junkPacketCount = 6;              # More junk packets
      junkPacketMinSize = 40;
      junkPacketMaxSize = 1200;
      initPacketJunkSize = 300;
      responsePacketJunkSize = 300;
      initPacketMagicHeader = 1234567890;
      responsePacketMagicHeader = 987654321;
      underloadPacketMagicHeader = 135792468;
      transportPacketMagicHeader = 246813579;
    };
  };

  dns = {
    localPort = 5353;
    upstreamServers = [ "1.1.1.1" "9.9.9.9" "8.8.8.8" ];
  };

  firewall = {
    allowedTCPPorts = [ 22 80 443 ];   # SSH, HTTP, HTTPS
    allowedUDPPorts = [ 53 ];          # DNS
    logLevel = "info";
  };

  monitoring = {
    enable = true;
    checkInterval = "2min";             # More frequent checks
    killSwitchTimeout = 15;             # Faster kill switch
  };
};
```

## Configuration Options

### Network Settings

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `network.lanInterfaces` | `[string]` | Network interfaces connected to LAN | `["enp3s0"]` |
| `network.lanSubnets` | `[string]` | LAN IP subnets to route through VPN | `["192.168.1.0/24"]` |
| `network.vpnGatewayIp` | `string` | This machine's IP on LAN (for DNS) | `"192.168.1.1"` |

### VPN Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `vpn.interface` | `string` | `"awg0"` | Amnezia WireGuard interface name |
| `vpn.configFile` | `path` | - | Path to Amnezia WG config file |
| `vpn.serverIp` | `string` | - | VPN server hostname or IP |
| `vpn.serverPort` | `port` | `51820` | VPN server port |

### Amnezia Obfuscation Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `vpn.amnezia.junkPacketCount` | `int` | `4` | Number of junk packets for obfuscation |
| `vpn.amnezia.junkPacketMinSize` | `int` | `50` | Minimum junk packet size |
| `vpn.amnezia.junkPacketMaxSize` | `int` | `1000` | Maximum junk packet size |
| `vpn.amnezia.initPacketJunkSize` | `int` | `200` | Initial packet junk data size |
| `vpn.amnezia.responsePacketJunkSize` | `int` | `200` | Response packet junk data size |

### DNS Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dns.localPort` | `port` | `5353` | Local DNS over HTTPS port |
| `dns.upstreamServers` | `[string]` | `["1.1.1.1", "9.9.9.9"]` | Fallback DNS servers |

### Firewall Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `firewall.allowedTCPPorts` | `[port]` | `[22]` | TCP ports accessible from LAN |
| `firewall.allowedUDPPorts` | `[port]` | `[]` | UDP ports accessible from LAN |
| `firewall.logLevel` | `enum` | `"warn"` | nftables log level |

### Monitoring Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `monitoring.enable` | `bool` | `true` | Enable VPN monitoring |
| `monitoring.checkInterval` | `string` | `"5min"` | Health check frequency |
| `monitoring.killSwitchTimeout` | `int` | `30` | Kill switch activation delay (seconds) |

## Setup Instructions

### 1. Prepare Amnezia WireGuard Configuration

First, obtain your Amnezia WireGuard configuration file from your VPN provider:

```bash
# Create configuration directory
sudo mkdir -p /etc/amnezia-wg

# Place your configuration file
sudo cp your-amnezia-config.conf /etc/amnezia-wg/client.conf
sudo chmod 600 /etc/amnezia-wg/client.conf
```

### 2. Add Module to Your NixOS Configuration

```nix
# In your configuration.nix or flake.nix
{
  imports = [
    ./modules/amnezia-vpn-gateway
  ];

  services.amneziaVpnGateway = {
    enable = true;
    # ... your configuration
  };
}
```

### 3. Configure LAN Clients

Set your LAN clients to use this machine as their:
- **Gateway**: Point default route to this machine's IP
- **DNS Server**: Set DNS to this machine's IP

Example for a client machine:
```bash
# Set gateway (replace with your gateway IP)
ip route add default via 192.168.1.1

# Set DNS (replace with your gateway IP)
echo "nameserver 192.168.1.1" > /etc/resolv.conf
```

### 4. Apply Configuration

```bash
# Rebuild and activate
sudo nixos-rebuild switch

# Verify services are running
systemctl status amnezia-wg
systemctl status unbound-system
systemctl status unbound-vpn
```

## Monitoring and Troubleshooting

### Check VPN Status

```bash
# Check Amnezia WireGuard status
sudo awg show

# Check VPN interface
ip addr show awg0

# Test external IP
curl -4 icanhazip.com
```

### Monitor DNS Resolution

```bash
# Test local DNS over HTTPS
dig @127.0.0.1 -p 5353 google.com

# Test VPN DNS (from LAN client)
dig @192.168.1.1 google.com
```

### View Logs

```bash
# VPN service logs
journalctl -u amnezia-wg -f

# DNS logs
journalctl -u unbound-system -f
journalctl -u unbound-vpn -f

# Kill switch monitoring
journalctl -u vpn-killswitch -f

# Leak detection
journalctl -u vpn-leak-detection -f

# nftables logs
journalctl -k | grep -i nft
```

### Debug Network Rules

```bash
# View active nftables rules
sudo nft list ruleset

# Check specific sets
sudo nft list set inet filter vpn_endpoints
sudo nft list set inet filter allowed_lan_ips

# Monitor packet flow with logging
sudo nft monitor
```

### Test Kill Switch

```bash
# Simulate VPN failure
sudo systemctl stop amnezia-wg

# Check if traffic is blocked (should fail)
curl -4 --max-time 10 icanhazip.com

# Restart VPN
sudo systemctl start amnezia-wg
```

## Security Features

### 🛡️ **Traffic Isolation**
- All forwarded traffic must go through VPN interface
- No direct internet access for LAN traffic
- Automatic blocking when VPN is down

### 🔍 **Leak Prevention**
- DNS leak prevention through DoH over VPN
- IP leak detection and monitoring
- Kill switch for immediate traffic blocking
- IPv6 disabled to prevent leaks

### 🕵️ **Traffic Obfuscation**
- Amnezia WireGuard's advanced obfuscation
- Customizable junk packet injection
- Magic header manipulation
- ISP and DPI evasion

### 🔐 **DNS Security**
- DNS over HTTPS (DoH) encryption
- DNSSEC validation
- No-log DNS providers
- Separate DNS streams for system vs VPN traffic

## Troubleshooting Common Issues

### VPN Won't Connect

1. **Check VPN endpoint resolution**:
   ```bash
   journalctl -u update-vpn-endpoints
   sudo nft list set inet filter vpn_endpoints
   ```

2. **Verify configuration file**:
   ```bash
   sudo awg-quick up /etc/amnezia-wg/client.conf
   ```

3. **Check firewall rules**:
   ```bash
   sudo nft list chain inet filter output
   ```

### DNS Not Working

1. **Check local DNS service**:
   ```bash
   systemctl status unbound-system
   dig @127.0.0.1 -p 5353 google.com
   ```

2. **Check VPN DNS service**:
   ```bash
   systemctl status unbound-vpn
   dig @192.168.1.1 google.com
   ```

3. **Verify DNS configuration**:
   ```bash
   cat /etc/resolv.conf
   ```

### Kill Switch Activated

1. **Check VPN interface status**:
   ```bash
   ip addr show awg0
   sudo awg show
   ```

2. **Review kill switch logs**:
   ```bash
   journalctl -u vpn-killswitch
   ```

3. **Manually restart VPN**:
   ```bash
   sudo systemctl restart amnezia-wg
   ```

### No Internet Access

1. **Verify routing**:
   ```bash
   ip route show
   sudo nft list chain inet filter forward
   ```

2. **Check NAT rules**:
   ```bash
   sudo nft list chain ip nat postrouting
   ```

3. **Test VPN connectivity**:
   ```bash
   ping -I awg0 8.8.8.8
   ```

## Performance Considerations

- **CPU Usage**: Amnezia obfuscation adds ~5-10% CPU overhead
- **Bandwidth**: Junk packets reduce effective bandwidth by ~2-5%
- **Latency**: Obfuscation adds ~1-3ms latency
- **Memory**: Each DNS service uses ~50MB RAM

## Security Recommendations

1. **Change default ports** for additional security
2. **Use strong authentication** for VPN connection
3. **Regularly update** VPN server endpoints
4. **Monitor logs** for suspicious activity
5. **Test kill switch** functionality periodically
6. **Use unique obfuscation parameters** for your setup

## License

This module is provided under the same license as your NixOS configuration.

## Contributing

Contributions are welcome! Please test thoroughly before submitting changes, especially:
- Kill switch functionality
- DNS leak prevention
- Traffic routing rules
- Service dependencies