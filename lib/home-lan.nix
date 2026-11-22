# Home LAN (192.168.1.0/24) address map.
#
# This is the single source of truth for LAN addresses in this repo. Exposed
# as `outputs.lib.homeLan` (flake-modules/lib.nix) and as JSON for Terraform
# and CoreDNS (`nix build .#home-lan-json`). The UniFi DHCP reservations must
# match it. More hosts, MACs and DNS names arrive with the network-docs work.
#
# Transition rule:
#   - `ip` is the address the host has TODAY. Every consumer reads `ip`.
#   - `plannedIp` is its address in the new layout.
#   Nothing live changes until a later commit sets `ip = plannedIp` for a
#   host, after its UniFi reservation has moved. `ip = null` means the host
#   is not on the LAN (not installed yet, or inactive).
#
# Planned layout (last octet):
#   .1        gateway (UDM)
#   .2-.9     network gear          .10-.19  hypervisors and out-of-band
#   .20-.29   storage               .30-.39  k8s nodes
#   .40-.49   services              .50-.59  home automation
#   .60-.69   workstations          .70-.99  media and printers
#   .100-.239 DHCP pool             .240-.255 Cilium LB pool (192.168.1.240/28)
#
# Host fields:
#   ip, plannedIp  see above
#   mac            null when not recorded yet
#   role           net | oob | hypervisor | storage | k8s | service |
#                  automation | workstation | media
#   managedBy      "dhcp" (UniFi reservation, the default) or "device" (UniFi
#                  gear that sets its own address)
#   fqdn           derived: "<name>.lan"
#
# `moveBlockers` lists hosts whose plannedIp is still another host's live
# ip, and which host must move first (`nix eval .#lib.homeLan.moveBlockers`).
#
# Evaluation fails if two hosts share an `ip`, two share a `plannedIp`, an
# address is outside the subnet, or a `plannedIp` falls inside the DHCP or
# Cilium LB pool.
{ lib }:
let
  domain = "lan";
  subnet = "192.168.1.0/24";
  prefixLength = 24;
  gateway = "192.168.1.1";
  dhcpPool = { start = "192.168.1.100"; end = "192.168.1.239"; };
  # Matches CiliumLoadBalancerIPPool default-pool (192.168.1.240/28) in
  # home-cluster.
  ciliumLbPool = { start = "192.168.1.240"; end = "192.168.1.255"; };
  # .247 is proposed; only .246 is live today.
  dnsServers = [ "192.168.1.246" "192.168.1.247" ];
  services = {
    dns1 = { ip = "192.168.1.246"; aliases = [ "dns" ]; };
    dns2 = { ip = "192.168.1.247"; };
    ingress = { ip = "192.168.1.240"; };
  };

  rawHosts = {
    # Network gear (UniFi sets these itself).
    usw-pro-24 = { ip = "192.168.1.76"; plannedIp = "192.168.1.2"; role = "net"; managedBy = "device"; };
    office-switch = { ip = "192.168.1.57"; plannedIp = "192.168.1.3"; role = "net"; managedBy = "device"; };
    living-room-switch = { ip = "192.168.1.95"; plannedIp = "192.168.1.4"; role = "net"; managedBy = "device"; };
    ap-office = { ip = "192.168.1.21"; plannedIp = "192.168.1.5"; role = "net"; managedBy = "device"; };
    ap-living-room = { ip = "192.168.1.29"; plannedIp = "192.168.1.6"; role = "net"; managedBy = "device"; };
    ap-ac-lr = { ip = "192.168.1.172"; plannedIp = "192.168.1.7"; role = "net"; managedBy = "device"; };

    # Hypervisors and out-of-band.
    home-kvm-hypervisor-1 = {
      ip = "192.168.1.10";
      plannedIp = "192.168.1.10";
      # Locally administered MAC of the br0 bridge, pinned by the host's
      # systemd-networkd netdev so the reservation survives a rebuild.
      mac = "62:95:4d:75:14:61";
      role = "hypervisor";
    };
    home-kvm-hypervisor-1-ipmi = { ip = "192.168.1.144"; plannedIp = "192.168.1.11"; mac = "9c:6b:00:e2:36:51"; role = "oob"; };
    pikvm = { ip = "192.168.1.111"; plannedIp = "192.168.1.12"; role = "oob"; };
    pikvm-wifi = { ip = "192.168.1.112"; plannedIp = "192.168.1.13"; role = "oob"; };

    # Storage.
    # Not .20: UniFi reserves 192.168.1.20 as its device fallback address
    # and rejects it as a fixed IP (api.err.InvalidFixedIP).
    home-storage-server-1 = { ip = "192.168.1.22"; plannedIp = "192.168.1.22"; mac = "52:54:00:69:9c:5c"; role = "storage"; };

    # k8s nodes.
    home-k8s-master-1 = { ip = "192.168.1.30"; plannedIp = "192.168.1.30"; mac = "52:54:00:0a:29:2c"; role = "k8s"; };
    # Not installed yet, so it starts on its planned address.
    home-k8s-server-1 = { ip = "192.168.1.31"; plannedIp = "192.168.1.31"; mac = "00:01:c0:28:8b:0f"; role = "k8s"; };
    home-k8s-server-2 = { ip = null; plannedIp = "192.168.1.32"; role = "k8s"; };

    # Services.
    download-server-1 = { ip = "192.168.1.40"; plannedIp = "192.168.1.40"; mac = "52:54:00:0a:29:2d"; role = "service"; };
    # Inactive VM.
    home-vpn-gateway-1 = { ip = null; plannedIp = "192.168.1.41"; role = "service"; };

    # Home automation.
    homeassistant = { ip = "192.168.1.16"; plannedIp = "192.168.1.50"; mac = "20:f8:3b:01:42:e9"; role = "automation"; };
    hive-hub = { ip = "192.168.1.9"; plannedIp = "192.168.1.51"; mac = "00:1c:2b:b4:d8:28"; role = "automation"; };
    hue-bridge = { ip = "192.168.1.69"; plannedIp = "192.168.1.52"; mac = "00:17:88:66:4d:2f"; role = "automation"; };
    smartthings-hub = { ip = "192.168.1.26"; plannedIp = "192.168.1.53"; mac = "d0:52:a8:a6:71:4b"; role = "automation"; };
    emonpi = { ip = "192.168.1.113"; plannedIp = "192.168.1.54"; mac = "b8:27:eb:9d:01:57"; role = "automation"; };
    openevse = { ip = "192.168.1.232"; plannedIp = "192.168.1.55"; mac = "ac:67:b2:0b:30:44"; role = "automation"; };
    tasmota-67ec7f = { ip = "192.168.1.158"; plannedIp = "192.168.1.56"; mac = "e8:db:84:67:ec:7f"; role = "automation"; };
    # Interim reservation: frees .40 for download-server-1 before the office
    # switch leaves .57.
    plug-d5a4d7 = { ip = "192.168.1.58"; plannedIp = "192.168.1.57"; mac = "34:98:7a:d5:a4:d7"; role = "automation"; };

    # Workstations.
    ali-desktop = { ip = "192.168.1.187"; plannedIp = "192.168.1.60"; mac = "9c:6b:00:1e:db:6d"; role = "workstation"; };
    tower = { ip = "192.168.1.94"; plannedIp = "192.168.1.61"; role = "workstation"; };
    ali-laptop-wifi = { ip = "192.168.1.11"; plannedIp = "192.168.1.62"; role = "workstation"; };
    ali-framework-laptop-wifi = { ip = "192.168.1.39"; plannedIp = "192.168.1.63"; role = "workstation"; };
    ali-work-laptop = { ip = "192.168.1.107"; plannedIp = "192.168.1.64"; role = "workstation"; };
    aliju-steamdeck = { ip = "192.168.1.67"; plannedIp = "192.168.1.65"; role = "workstation"; };

    # Media and printers.
    shield-tv = { ip = "192.168.1.225"; plannedIp = "192.168.1.70"; mac = "00:04:4b:fa:96:35"; role = "media"; };
    qidi-max4 = { ip = "192.168.1.181"; plannedIp = "192.168.1.71"; mac = "58:e4:eb:88:b6:6a"; role = "media"; };
    camera-living-room = { ip = "192.168.1.92"; plannedIp = "192.168.1.72"; role = "media"; managedBy = "device"; };
  };

  hosts = lib.mapAttrs
    (name: host: { mac = null; managedBy = "dhcp"; } // host // { fqdn = "${name}.${domain}"; })
    rawHosts;

  # The checks below compare last octets, which is only sound inside one /24.
  netPrefix = lib.concatStringsSep "." (lib.take 3 (lib.splitString "." gateway)) + ".";
  octet = ip: lib.toInt (lib.last (lib.splitString "." ip));
  inPool = pool: ip: octet ip >= octet pool.start && octet ip <= octet pool.end;

  # name=address pairs for one field, skipping hosts where it is null.
  pairs = field:
    lib.filter (p: p.addr != null)
      (lib.mapAttrsToList (name: host: { inherit name; addr = host.${field}; }) hosts);
  duplicates = field:
    let
      grouped = lib.groupBy (p: p.addr) (pairs field);
    in
    lib.mapAttrsToList (addr: ps: "${addr} (${lib.concatMapStringsSep ", " (p: p.name) ps})")
      (lib.filterAttrs (_: ps: lib.length ps > 1) grouped);
  outsideSubnet = field:
    map (p: "${p.name}.${field} = ${p.addr}")
      (lib.filter (p: !(lib.hasPrefix netPrefix p.addr)) (pairs field));
  plannedInPools =
    map (p: "${p.name}.plannedIp = ${p.addr}")
      (lib.filter (p: inPool dhcpPool p.addr || inPool ciliumLbPool p.addr) (pairs "plannedIp"));

  # A host whose plannedIp is another host's live ip cannot move until that
  # host does; the duplicate-ip check rejects the flip if it is done first.
  liveOwner = lib.listToAttrs (map (p: lib.nameValuePair p.addr p.name) (pairs "ip"));
  moveBlockers = lib.concatMap
    (p:
      let owner = liveOwner.${p.addr} or null;
      in lib.optional (owner != null && owner != p.name)
        { host = p.name; plannedIp = p.addr; waitsFor = owner; })
    (pairs "plannedIp");

  errors =
    map (d: "duplicate ip ${d}") (duplicates "ip")
    ++ map (d: "duplicate plannedIp ${d}") (duplicates "plannedIp")
    ++ map (e: "outside ${subnet}: ${e}") (outsideSubnet "ip" ++ outsideSubnet "plannedIp")
    ++ map (e: "inside the DHCP or Cilium LB pool: ${e}") plannedInPools;

  homeLan = {
    inherit domain subnet prefixLength gateway dhcpPool ciliumLbPool dnsServers services hosts moveBlockers;
  };
in
if errors == [ ] then homeLan
else throw "lib/home-lan.nix:\n  ${lib.concatStringsSep "\n  " errors}"
