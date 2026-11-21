# /etc/hosts entries for every home LAN host with a live address, taken from
# lib/home-lan.nix. Names then resolve even when the LAN DNS server is down,
# which matters on hosts that the DNS service itself depends on.
{ config, lib, outputs, ... }:
let
  cfg = config.modules.homeLanHosts;
  live = lib.filterAttrs (_: host: host.ip != null) outputs.lib.homeLan.hosts;
in
{
  options.modules.homeLanHosts.enable =
    lib.mkEnableOption "/etc/hosts entries for the home LAN address map";

  config = lib.mkIf cfg.enable {
    networking.hosts = lib.mapAttrs' (name: host: lib.nameValuePair host.ip [ host.fqdn name ]) live;
  };
}
