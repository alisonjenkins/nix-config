# Holds the LAN's DNS addresses (services.dns1 and dns2 in lib/home-lan.nix)
# on whichever k8s node can answer lookups, using VRRP between the nodes.
#
# Cilium's L2 announcements need the API server, so a Cilium LB IP goes dark
# whenever master-1 (the only control plane) is down. keepalived has no such
# dependency. The DNS server on the address is the hostNetwork CoreDNS in
# home-cluster (coredns-lan/host-network.yaml), bound to the VIPs and 127.0.0.1.
#
# The check is a real lookup through that CoreDNS, so it fails when the
# node's path to the VPN resolvers fails. If every node fails, nobody holds
# the addresses and LAN DNS fails closed instead of leaking.
{ config, lib, outputs, pkgs, ... }:
let
  cfg = config.modules.k8sDnsVip;
  homeLan = outputs.lib.homeLan;
  self = homeLan.hosts.${config.networking.hostName}.ip;
  peers = lib.filter (ip: ip != self) (map (name: homeLan.hosts.${name}.ip) cfg.nodes);
  vips = {
    lan-dns1 = { ip = homeLan.services.dns1.ip; virtualRouterId = 46; };
    lan-dns2 = { ip = homeLan.services.dns2.ip; virtualRouterId = 47; };
  };
  # keepalived runs the script without a shell, so the pipe needs a wrapper.
  # dig +short prints timeout errors to stdout, so match an address, not any line.
  check = pkgs.writeShellScript "lan-dns-check" ''
    ${pkgs.dnsutils}/bin/dig +time=1 +tries=1 +short @127.0.0.1 cloudflare.com A | ${pkgs.gnugrep}/bin/grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
  '';
in
{
  options.modules.k8sDnsVip = {
    enable = lib.mkEnableOption "the VRRP-held LAN DNS addresses on k8s nodes";

    interface = lib.mkOption {
      type = lib.types.str;
      description = "LAN interface that carries the addresses.";
    };

    priority = lib.mkOption {
      type = lib.types.ints.between 1 254;
      description = "VRRP priority. The healthy node with the highest one holds the addresses.";
    };

    nodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "home-k8s-master-1" "home-k8s-server-1" ];
      description = "lib/home-lan.nix hosts that run keepalived for the addresses.";
    };
  };

  config = lib.mkIf cfg.enable {
    # CoreDNS binds the VIPs before this node holds them.
    boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

    services.keepalived = {
      enable = true;
      openFirewall = true;
      enableScriptSecurity = true;

      vrrpScripts.lan-dns = {
        script = "${check}";
        interval = 2;
        fall = 2;
        rise = 2;
        user = "keepalived_script";
      };

      vrrpInstances = lib.mapAttrs (_: vip: {
        inherit (cfg) interface priority;
        inherit (vip) virtualRouterId;
        state = "BACKUP";
        unicastSrcIp = self;
        unicastPeers = peers;
        virtualIps = [ { addr = "${vip.ip}/${toString homeLan.prefixLength}"; } ];
        trackScripts = [ "lan-dns" ];
      }) vips;
    };

    users.users.keepalived_script = {
      isSystemUser = true;
      group = "keepalived_script";
    };
    users.groups.keepalived_script = { };
  };
}
