# 0063. Unlock homelab LUKS over initrd SSH, with static addresses and an on-host key

- Status: Accepted, pending live test
- Date: 2026-11-22

## Context

The hypervisor, home-storage-server-1 and download-server-1 have LUKS roots.
After a reboot each one waits at a passphrase prompt. Before this change the
only way to answer was a console: IPMI for the hypervisor, `virsh console` for
the VMs. home-k8s-server-1 already had initrd SSH through
`modules/initrd-ssh.nix`, with DHCP and a host key built in the Nix store.

## Decision

Enable `modules.initrd-ssh` on all three hosts, and extend the module:

- `network.address`, `network.gateway` and `network.matchConfig` give the
  initrd a static address, taken from `lib/home-lan.nix` and matched by MAC.
- The hypervisor builds the same `br0` in the initrd as in stage 2, with the
  same pinned MAC, and puts its address on `br0`.
- `hostKeyPath` points at a key file on the host. The bootloader copies it
  into the initrd as an initrd secret.
- With a static address, `flushBeforeStage2` defaults to true.
- `just unlock-homelab` unlocks in boot order: hypervisor, storage, download.

## Things that are not obvious

- **DHCP is behind the prompt it serves.** The UDM gives out leases, but a
  VM's reservation is keyed on its MAC. The hypervisor's reservation is for
  br0's MAC, not a physical port's. A static address removes both
  dependencies.
- **The hypervisor needs br0 in the initrd.** Its LAN address and pinned MAC
  live on the bridge. If the initrd used the ixgbe port, .10 would appear on a
  different MAC during unlock, and the UDM's ARP entry would flip at each boot.
- **Flush before stage 2.** With systemd in the initrd, networkd keeps its
  addresses into stage 2 by default. download-server-1 runs NetworkManager and
  a VPN kill switch, which must start from an unconfigured NIC.
- **Store keys can leak.** The build-time key sits in the Nix store, and
  build outputs can be pushed to the binary cache. It also changes at each
  nixpkgs bump. A file on the host does neither.
- **The key must exist before the switch.** A missing initrd secret makes the
  bootloader install fail.

## Alternatives rejected

- **DHCP in the initrd**, as on home-k8s-server-1. It depends on the
  reservation matching the initrd's MAC, which is false on the hypervisor.
- **Ordering VM autostart in libvirt.** Each VM waits at its own prompt
  anyway, so order comes from the unlock sequence, not from start times.
- **TPM unlock.** The VMs have no vTPM, and the hypervisor's TPM binding is
  a separate decision.

## Consequences

- Each host needs a one-time key creation before its first deploy with this.
- Physical access to the boot partition reveals the initrd host key. It does
  not reveal the LUKS passphrase.
- home-k8s-master-1 is not encrypted and is not covered.
  home-vpn-gateway-1 is shut off and has no address, so it is not covered.

## Evidence

- `nix eval` of `boot.initrd.systemd.network` shows `10-initrd-net` with
  192.168.1.10/24 on br0 and the `20-br0` netdev with MAC
  62:95:4d:75:14:61, and MAC-matched static addresses on the two VMs.
- `lsblk` on the live hosts: md127 -> os_raid1_crypt on the hypervisor, vda2
  crypto_LUKS on download-server-1, no crypt layer on home-k8s-master-1.

## Revisit when

- A first live unlock fails to reach port 2222 on any host.
- The VMs get a vTPM, which would allow unattended unlock.
