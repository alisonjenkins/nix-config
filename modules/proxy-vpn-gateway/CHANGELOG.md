# Changelog - Proxy VPN Gateway Module

## [Fixed] - 2024

### Summary
Fixed multiple syntax errors and added support for VPN endpoint hostnames with automatic IP resolution and firewall configuration.

### Fixed Syntax Errors

1. **Misplaced `in` keyword** (line 70)
   - **Before**: `config = mkIf cfg.enable { let ... }`
   - **After**: `config = mkIf cfg.enable (let ... in { ... });`
   - **Impact**: This was causing a Nix evaluation error preventing the module from being used

2. **Malformed if expression** (line 184)
   - **Before**: `${# Nix's 'if' to conditionally add the authentication argument. if cfg.proxy.auth == "none" then "" else "-u ${cfg.proxy.auth}" }`
   - **After**: `${if cfg.proxy.auth == "none" then "" else "-u ${cfg.proxy.auth}"}`
   - **Impact**: Comments are not allowed in string interpolations

3. **Singular/plural option mismatches**
   - **Before**: Referenced `cfg.lanInterface` (singular) and `cfg.lanSubnet` (singular)
   - **After**: Uses `cfg.lanInterfaces` (plural) and `cfg.lanSubnets` (plural) correctly
   - **Impact**: These options were defined as lists but referenced as single values

4. **Missing interface name quoting in nftables rules**
   - **Before**: `iifname ${lanInterface}`
   - **After**: `iifname "${lanInterface}"`
   - **Impact**: Interface names with special characters could cause nftables parsing errors

### New Features

#### VPN Endpoints Support

Added a new option `vpnEndpoints` that allows specifying VPN server hostnames:

```nix
services.proxyVpnGateway = {
  vpnEndpoints = [
    "vpn.example.com"
    "backup-vpn.example.org"
  ];
};
```

**Implementation details:**
- New ipset `vpn_endpoints` is created in nftables when VPN endpoints are configured
- DNS resolution runs periodically (same schedule as other exception domains)
- Firewall automatically allows connections to these endpoints on ANY interface
- This is critical for establishing VPN connections

### Improved Firewall Rules

1. **Multiple LAN subnets support**
   - Changed from single `cfg.lanSubnet` to properly iterate over `cfg.lanSubnets`
   - Now supports configurations with multiple LAN segments

2. **VPN endpoint access**
   - Added firewall rule: `ip daddr @vpn_endpoints accept` (applied to all interfaces)
   - This allows the system to connect to VPN servers before the VPN tunnel is established

3. **Interface name safety**
   - All interface names are now properly quoted in nftables rules

### Code Cleanup

1. **Removed unused microsocksLauncher**
   - The launcher was defined but never used
   - Functionality is now directly in the systemd service ExecStart

2. **Improved service definition**
   - Uses `builtins.head cfg.lanInterfaces` to select the first interface
   - Full paths to binaries (${pkgs.iproute2}/bin/ip, ${pkgs.gnugrep}/bin/grep)

### Migration Notes

**No configuration changes required** if you're already using the module with:
- Multiple `lanInterfaces` 
- Multiple `lanSubnets`
- No VPN endpoints specified

**Recommended changes:**

1. **Add VPN endpoints** to ensure reliable VPN connectivity:
   ```nix
   services.proxyVpnGateway = {
     vpnEndpoints = [ "your-vpn-server.com" ];
   };
   ```

2. **Verify your configuration** includes required options:
   - `lanInterfaces = [ "enp3s0" ];` (list, not single value)
   - `lanSubnets = [ "192.168.1.0/24" ];` (list, not single value)
   - `vpnInterface = "wg0";` (required)

### Breaking Changes

None - All changes are backwards compatible with existing valid configurations.

### Bug Fixes

- Fixed crash when using multiple LAN interfaces or subnets
- Fixed nftables syntax errors with unquoted interface names
- Fixed Nix evaluation errors preventing module instantiation
