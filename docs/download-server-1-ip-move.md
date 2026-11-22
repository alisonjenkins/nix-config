# Moving download-server-1 to its planned address

download-server-1 (ds1) is the VM that runs the download stack and the
VPN-only DNS resolver. On 2026-11-22 it moved from `192.168.1.132` to
`192.168.1.40`, its `plannedIp` in `lib/home-lan.nix`. This page records the
order that worked and the traps found on the way, so the next move of a
NetworkManager host goes faster.

## Order used

Each step is a merge or a deploy on its own. The house keeps working after
each one.

1. Free the target address. `.40` was held by a smart plug on a dynamic
   lease. Give the plug an interim reservation (`.58`) first: nix-config
   #1027, terraform `unifi` #4.
2. Make ds1 answer on both addresses (nix-config #1028). `lanAddresses` held
   `ip` and `plannedIp`, and Unbound listened on both.
3. Point every consumer at the new address, keeping the old one as a
   fallback (home-cluster #1886). That covered the CoreDNS forwarders, the
   download-stack A records, the Jellyseerr Endpoints and WAF egress policy.
4. Set `ip = plannedIp` (nix-config #1029) and update the UniFi reservation
   (terraform `unifi` #5). Then:
   - run `just backup`, then `just apply` in `terraform/unifi`;
   - deploy home-k8s-master-1 and home-k8s-server-1 for `/etc/hosts`;
   - deploy ds1 last, by address (see below).
5. Remove the old address everywhere (home-cluster #1888).

## Traps

- **The old NetworkManager profile wins at boot.**
  `NetworkManager-ensure-profiles` runs after NM autoconnect. If the
  imperative profile (`Wired connection 1`) still autoconnects, it comes up
  first and the declarative `lan` profile never starts. Set it to
  `connection.autoconnect no` before the reboot, then delete it once the
  move is done.
- **A deploy does not re-apply the profile.** Changing the `lan` profile on
  disk leaves the live addresses alone. Run `sudo nmcli con up lan` after
  the deploy.
- **Services keep their bind address.** `microsocks-proxy` reads its listen
  IP at start. Restart it after the address changes:
  `sudo systemctl restart microsocks-proxy`.
- **ds1 drops ICMP.** `ping` proves nothing. Test with `ssh` or `nc -zv`.
- **Tailscale SSH to ds1 times out.** Use the LAN.
- **The `.lan` name lags.** It can still resolve to the old address, so
  deploy by address and keep the known host key:

  ```bash
  nix develop -c deploy .#download-server-1 --skip-checks --hostname 192.168.1.40 --ssh-opts "-o HostKeyAlias=download-server-1.lan"
  ```

## When ds1 is off the LAN

- Jump over the storage jumbo network:

  ```bash
  ssh -J home-storage-server-1.lan ali@10.10.10.1
  ```

- ds1 has no serial getty. To see its console, take a screenshot from the
  hypervisor:

  ```bash
  ssh home-kvm-hypervisor-1.lan virsh screenshot download-server-1 /tmp/ds1.png
  ```

## Leak check

Run this after every network change on ds1. It must capture 0 packets while
you send lookups to `192.168.1.40`:

```bash
sudo tcpdump -ni enp1s0 '(port 53 or port 853) and not (src net 192.168.1.0/24 and dst net 192.168.1.0/24)'
```

On 2026-11-22T10:33Z it captured 0 packets after 15 test lookups.
