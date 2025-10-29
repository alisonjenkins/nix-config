#!/usr/bin/env bash

# Amnezia VPN Gateway Setup Script
# This script helps set up the basic configuration for the VPN gateway

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/amnezia-wg"
BACKUP_DIR="/etc/amnezia-wg/backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user with sudo access."
        exit 1
    fi
}

# Check if sudo is available
check_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        print_error "sudo is required but not installed. Please install sudo first."
        exit 1
    fi
}

# Create configuration directory
setup_config_dir() {
    print_status "Setting up configuration directory..."
    
    sudo mkdir -p "$CONFIG_DIR"
    sudo mkdir -p "$BACKUP_DIR"
    sudo chmod 700 "$CONFIG_DIR"
    sudo chmod 700 "$BACKUP_DIR"
    
    print_success "Configuration directory created at $CONFIG_DIR"
}

# Generate example WireGuard configuration
generate_example_config() {
    local config_file="$CONFIG_DIR/client.conf.example"
    
    print_status "Generating example WireGuard configuration..."
    
    sudo tee "$config_file" > /dev/null << 'EOF'
[Interface]
# Client private key (generate with: wg genkey)
PrivateKey = YOUR_PRIVATE_KEY_HERE
# Client IP address on VPN network
Address = 10.8.0.2/24
# DNS servers to use when connected (will be overridden by our DoH setup)
DNS = 1.1.1.1, 9.9.9.9

# Amnezia obfuscation parameters (will be added automatically by NixOS module)
# Jc = 4
# Jmin = 50
# Jmax = 1000
# S1 = 200
# S2 = 200
# H1 = 1234567890
# H2 = 987654321 
# H3 = 135792468
# H4 = 246813579

[Peer]
# Server public key
PublicKey = YOUR_SERVER_PUBLIC_KEY_HERE
# Server endpoint (IP:port or hostname:port)
Endpoint = vpn.example.com:51820
# Allowed IPs (0.0.0.0/0 routes all traffic through VPN)
AllowedIPs = 0.0.0.0/0
# Keep alive interval
PersistentKeepalive = 25
EOF

    sudo chmod 600 "$config_file"
    print_success "Example configuration created at $config_file"
    print_warning "Remember to replace YOUR_PRIVATE_KEY_HERE and YOUR_SERVER_PUBLIC_KEY_HERE with actual keys!"
}

# Detect network interfaces
detect_interfaces() {
    print_status "Detecting network interfaces..."
    
    echo -e "\n${BLUE}Available network interfaces:${NC}"
    ip -o link show | awk -F': ' '{print "  " $2}' | grep -v lo | head -10
    
    echo -e "\n${BLUE}Interface details:${NC}"
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -5); do
        if ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
            local ip=$(ip addr show "$iface" | grep "inet " | awk '{print $2}' | head -1)
            echo -e "  ${GREEN}$iface${NC}: $ip (UP)"
        else
            echo -e "  ${YELLOW}$iface${NC}: No IP (DOWN)"
        fi
    done
}

# Generate NixOS configuration snippet
generate_nixos_config() {
    local config_file="$SCRIPT_DIR/generated-config.nix"
    
    print_status "Generating NixOS configuration snippet..."
    
    # Get the first active interface with an IP
    local lan_interface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}' || echo "enp3s0")
    local lan_ip=$(ip addr show "$lan_interface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -1 || echo "192.168.1.1")
    local lan_subnet=$(ip route | grep "$lan_interface" | grep -E "192\.168\.|10\.|172\." | awk '{print $1}' | head -1 || echo "192.168.1.0/24")
    
    tee "$config_file" > /dev/null << EOF
# Generated Amnezia VPN Gateway Configuration
# Add this to your NixOS configuration.nix or include it as a module

{
  imports = [
    ./modules/amnezia-vpn-gateway
  ];

  services.amneziaVpnGateway = {
    enable = true;

    network = {
      # Detected LAN interface
      lanInterfaces = [ "$lan_interface" ];
      # Detected LAN subnet  
      lanSubnets = [ "$lan_subnet" ];
      # This machine's IP on LAN
      vpnGatewayIp = "$lan_ip";
    };

    vpn = {
      interface = "awg0";
      configFile = "/etc/amnezia-wg/client.conf";
      serverIp = "vpn.example.com"; # Replace with your VPN server
      serverPort = 51820;

      # Amnezia obfuscation settings (customize these!)
      amnezia = {
        junkPacketCount = 4;
        junkPacketMinSize = 50;
        junkPacketMaxSize = 1000;
        initPacketJunkSize = 200;
        responsePacketJunkSize = 200;
        # Change these magic headers for your setup!
        initPacketMagicHeader = 1234567890;
        responsePacketMagicHeader = 987654321;
        underloadPacketMagicHeader = 135792468;
        transportPacketMagicHeader = 246813579;
      };
    };

    dns = {
      localPort = 5353;
      upstreamServers = [ "1.1.1.1" "9.9.9.9" ];
    };

    firewall = {
      allowedTCPPorts = [ 22 ]; # SSH access
      logLevel = "warn";
    };

    monitoring = {
      enable = true;
      checkInterval = "5min";
      killSwitchTimeout = 30;
    };
  };

  # Additional recommended settings
  networking.firewall.enable = lib.mkForce false; # Disabled in favor of nftables
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
}
EOF

    print_success "NixOS configuration generated at $config_file"
    print_status "Detected settings:"
    echo -e "  LAN Interface: ${GREEN}$lan_interface${NC}"
    echo -e "  LAN IP: ${GREEN}$lan_ip${NC}"
    echo -e "  LAN Subnet: ${GREEN}$lan_subnet${NC}"
}

# Generate key pair
generate_keys() {
    print_status "Generating WireGuard key pair..."
    
    if ! command -v wg >/dev/null 2>&1; then
        print_warning "WireGuard tools not found. Keys will need to be generated manually."
        return
    fi
    
    local private_key=$(wg genkey)
    local public_key=$(echo "$private_key" | wg pubkey)
    
    echo -e "\n${BLUE}Generated Keys:${NC}"
    echo -e "Private Key: ${YELLOW}$private_key${NC}"
    echo -e "Public Key:  ${GREEN}$public_key${NC}"
    echo -e "\n${RED}IMPORTANT:${NC} Store the private key securely and never share it!"
    echo -e "Send the public key to your VPN server administrator."
}

# Main setup function
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║          Amnezia VPN Gateway Setup                ║"
    echo "║                                                   ║"
    echo "║  This script will help you set up the basic      ║"
    echo "║  configuration for your VPN gateway.             ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    check_root
    check_sudo

    print_status "Starting setup process..."

    # Setup configuration directory
    setup_config_dir

    # Generate example configuration
    generate_example_config

    # Detect network interfaces
    detect_interfaces

    # Generate NixOS configuration
    generate_nixos_config

    # Generate keys if possible
    if command -v wg >/dev/null 2>&1; then
        echo -e "\n${BLUE}Would you like to generate a WireGuard key pair? (y/N)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            generate_keys
        fi
    fi

    # Final instructions
    echo -e "\n${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Setup completed successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${BLUE}Next steps:${NC}"
    echo "1. Copy your actual VPN configuration to:"
    echo -e "   ${YELLOW}$CONFIG_DIR/client.conf${NC}"
    
    echo -e "\n2. Add the generated configuration to your NixOS config:"
    echo -e "   ${YELLOW}$SCRIPT_DIR/generated-config.nix${NC}"
    
    echo -e "\n3. Rebuild your NixOS configuration:"
    echo -e "   ${YELLOW}sudo nixos-rebuild switch${NC}"
    
    echo -e "\n4. Configure your LAN clients to use this machine as their gateway:"
    echo -e "   Gateway: ${GREEN}$(ip addr show "$(ip route get 8.8.8.8 | awk '{print $5; exit}')" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)${NC}"
    echo -e "   DNS: ${GREEN}$(ip addr show "$(ip route get 8.8.8.8 | awk '{print $5; exit}')" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)${NC}"
    
    echo -e "\n5. Monitor the services:"
    echo -e "   ${YELLOW}sudo systemctl status amnezia-wg${NC}"
    echo -e "   ${YELLOW}sudo journalctl -u amnezia-wg -f${NC}"
    
    echo -e "\n${BLUE}For more information, see:${NC}"
    echo -e "   ${YELLOW}$SCRIPT_DIR/README.md${NC}"
    
    echo -e "\n${RED}Important Security Notes:${NC}"
    echo "- Change the default magic headers in the configuration"
    echo "- Use strong WireGuard keys"
    echo "- Test the kill switch functionality"
    echo "- Monitor logs for any leak detection warnings"
}

# Run main function
main "$@"