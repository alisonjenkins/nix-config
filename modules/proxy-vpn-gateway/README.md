# Proxy VPN Gateway Module

This NixOS module provides a SOCKS5 proxy gateway that routes traffic through a VPN tunnel while allowing exceptions for specific domains and VPN endpoints.

## Features

- SOCKS5 proxy server using microsocks
- nftables-based firewall with strict VPN routing
- Automatic IP set updates for exception domains
- Support for multiple VPN endpoints with dynamic IP resolution
- Periodic DNS resolution to keep IP sets up-to-date

## Configuration Options

### Basic Options

- `enable`: Enable the proxy VPN gateway service
- `lanInterfaces`: List of network interfaces connected to LANs (e.g., `["enp3s0"]`)
- `lanSubnets`: List of IP subnets for your LANs (e.g., `["192.168.1.0/24"]`)
- `vpnInterface`: The virtual network interface for your VPN tunnel (e.g., `"wg0"`)

### Proxy Configuration

- `proxy.port`: TCP port for the SOCKS5 proxy (default: 1080)
- `proxy.auth`: Authentication for the proxy. Use `"none"` or `"user:pass"`

### Exception Domains

The module allows certain domains to bypass the VPN:

- `exceptions.dnsServers`: Public DNS servers for resolving exception domains
- `exceptions.domains.github`: GitHub-related domains (default includes github.com, api.github.com, etc.)
- `exceptions.domains.nix`: Nix binary cache domains (default: cache.nixos.org)

### VPN Endpoints

- `vpnEndpoints`: List of VPN endpoint hostnames or IP addresses that should be allowed through the firewall
  - This is essential for allowing the VPN connection itself to be established
  - Supports both hostnames and IP addresses
  - Example: `["vpn.example.com", "backup-vpn.example.org", "192.0.2.1", "198.51.100.42"]`

### Update Configuration

- `updateFrequency`: How often to update IP sets (default: "1h", uses systemd time format)

## Example Usage

```nix
services.proxyVpnGateway = {
  enable = true;

  lanInterfaces = [ "enp3s0" ];
  lanSubnets = [ "192.168.1.0/24" ];
  vpnInterface = "wg0";

  proxy = {
    port = 1080;
    auth = "none";
  };

  exceptions = {
    dnsServers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    domains = {
      github = [ "github.com" "api.github.com" ];
      nix = [ "cache.nixos.org" ];
    };
  };

  # VPN endpoints that should be accessible (hostnames or IP addresses)
  vpnEndpoints = [
    "vpn.example.com"
    "backup-vpn.example.org"
    "192.0.2.1"
  ];

  updateFrequency = "30min";
};
```

## How It Works

1. **Firewall Rules**: The module configures nftables with a strict drop policy, only allowing:
   - Established/related connections
   - Loopback traffic
   - SSH on LAN interfaces
   - SOCKS5 proxy access from LAN subnets
   - Traffic through the VPN interface
   - Exceptions: DNS to configured servers, access to exception domain IPs
   - VPN endpoint access (critical for establishing VPN connection)

2. **IP Sets**: Dynamic nftables IP sets are created for:
   - GitHub domains (`github_ips`)
   - Nix cache domains (`nix_caches`)
   - VPN endpoints (`vpn_endpoints`)

3. **Automatic Updates**: A systemd timer periodically resolves the configured domains and updates the IP sets, ensuring that IP changes are automatically handled.

## Firewall Behavior

The firewall implements a strict VPN-only policy:
- All traffic must go through the VPN interface except:
  - LAN-to-LAN traffic
  - DNS queries to configured servers
  - Traffic to exception domains (GitHub, Nix caches)
  - Traffic to VPN endpoints (to establish the VPN connection)

This prevents accidental leaks if the VPN connection drops.

## Troubleshooting

### VPN Cannot Connect

If your VPN fails to connect, ensure that:
1. The `vpnEndpoints` option includes all VPN server hostnames or IP addresses
2. The VPN endpoint IPs are being resolved correctly (check logs with `journalctl -u update-nft-sets`)
3. The firewall allows outbound traffic to VPN endpoints

### IP Set Not Updating

Check the update service logs:
```bash
journalctl -u update-nft-sets
```

Manually trigger an update:
```bash
systemctl start update-nft-sets
```

View current IP sets:
```bash
nft list set inet filter vpn_endpoints
nft list set inet filter github_ips
nft list set inet filter nix_caches
```
