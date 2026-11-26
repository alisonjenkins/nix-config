# Homelab LUKS unlock over SSH

The hypervisor and two of its VMs have LUKS roots. Each one stops at boot and
waits for its passphrase. Each runs an SSH server in the initrd on port 2222,
so you can type the passphrase from another machine. The shared module is
`modules/initrd-ssh.nix`. ADR 0063 records why it is built this way.

## Hosts

| Host | Address | Encrypted | Initrd SSH | Host key file |
|---|---|---|---|---|
| home-kvm-hypervisor-1 | 192.168.1.10 (br0) | yes | yes | `/etc/secrets/initrd/ssh_host_ed25519_key` |
| home-storage-server-1 | 192.168.1.22 | yes | yes | `/persistence/etc/secrets/initrd/ssh_host_ed25519_key` |
| download-server-1 | 192.168.1.40 | yes | yes | `/persistence/etc/secrets/initrd/ssh_host_ed25519_key` |
| home-k8s-server-1 | 192.168.1.31 | yes | yes (DHCP) | build-time key; see `docs/home-k8s-server-1.md` |
| home-k8s-master-1 | 192.168.1.30 | **no** | not needed | none |
| home-vpn-gateway-1 | none | yes (disko) | no | VM is shut off and has no address |

Addresses come from `lib/home-lan.nix`. The initrd uses them as static
addresses, matched by MAC (br0 on the hypervisor). So the unlock does not need
DHCP or DNS.

## Unlock order

1. **home-kvm-hypervisor-1.** libvirt starts the VMs only after this host is up.
2. **home-storage-server-1.** The other VMs mount its NFS exports.
3. **download-server-1.**

All VMs start at the same time and wait at their own prompts. Unlocking out of
order works, but a VM unlocked before storage starts without its NFS mounts.

## Unlock

Run this from a LAN machine with the primary SSH key:

```sh
just unlock-homelab
```

It goes through the hosts in the order above. It skips a host that already
answers on port 22. For each other host, it waits for port 2222, asks for the
passphrase, then waits for port 22 before moving on.

While it waits, it prints a status line every 30 seconds. The line shows the
VM's libvirt state (read from the hypervisor), whether the host answers ping,
and whether the port is open. It waits up to 300 seconds for the prompt. It
stops at once if the VM is shut off and prints the `virsh start` command. If
the prompt never opens, it offers to open the VM's serial console on the
hypervisor (`virsh console`), where the same prompt shows. Ctrl-] leaves the
console.

To unlock one host:

```sh
just unlock-homelab home-storage-server-1
```

By hand:

```sh
ssh -p 2222 root@192.168.1.22
systemd-tty-ask-password-agent
```

## Setting up a host

The host key must exist on the host **before** the first switch that enables
this. The bootloader copies it into the initrd when it installs. If the file
is missing, the bootloader install fails and the switch stops. Run this on
each host, with that host's path from the table:

```sh
sudo install -d -m 700 /persistence/etc/secrets/initrd
sudo ssh-keygen -t ed25519 -N "" -f /persistence/etc/secrets/initrd/ssh_host_ed25519_key
```

Then deploy. The new initrd only runs at the next reboot.

## If the unlock does not answer

- The hypervisor has IPMI at 192.168.1.11. Use its console to type the
  passphrase there.
- The VMs have their own consoles: `virsh console <vm>` on the hypervisor.
- home-storage-server-1 used to keep port 2222 closed for 5+ minutes. Its HBA
  driver (mpt3sas) scans every disk synchronously (`scsi_mod.scan=sync`), and
  that load sat in `systemd-modules-load`, which initrd networking waits for.
  The `load-mpt3sas` initrd unit now loads it instead. Networking and SSH come
  up at once, and switch-root still waits for the scan to finish.
- To go back, pick the previous generation in the boot menu.
