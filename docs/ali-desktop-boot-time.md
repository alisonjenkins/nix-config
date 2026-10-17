# ali-desktop boot time

Where boot time goes on `ali-desktop`, what was changed, and what was left
alone. Decision record: [ADR 0045](adr/0045-keep-an-extra-fast-keyslot-on-the-home-luks-volumes.md).

## Baseline

Measured 2026-10-16 with `systemd-analyze`, before any change.

| Phase | Time |
|---|---|
| Firmware | 12.7 s |
| Loader | 2.3 s |
| Kernel | 0.8 s |
| initrd | 13.8 s |
| Userspace | 12.7 s |
| Total | 42.3 s |

Commands: `systemd-analyze time`, `systemd-analyze blame`,
`systemd-analyze critical-chain`, `journalctl -b -o short-monotonic`.

## What cost time and what fixed it

### initrd: stale TPM2 policy on the root volume

The root volume's `systemd-tpm2` token binds PCR 11 only (`tpm2-pcrs: [11]`,
bank sha256). PCR 11 is a hash of the UKI contents, so every kernel or initrd
rebuild changes it and the token stops unsealing. systemd then falls back to a
typed passphrase, and the wait for typing is most of the 13.8 s.

Check the token: `sudo cryptsetup token export --token-id 1 /dev/<root>`
(`luksDump | grep` truncates the PCR list). Look for the policy failure in
the boot log: `journalctl -b -o short-monotonic | grep -i 'TPM policy'`.

Re-enrol after a rebuild that changes the UKI:

```sh
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=11 /dev/<root>
```

Do not bind PCR 15 (see `modules/luksPCR15` and the memory notes) or PCR 7
(unstable on this board, and Secure Boot is off in firmware even though
`bootLoader = "secure-boot"`). Not fixed: the re-enrol is manual after every
UKI change. Durable options are a signed PCR 11 policy or PCR 7 with Secure
Boot actually on.

### initrd: argon2i on the home volumes

`home1` and `home2` are LUKS2 with an argon2i slot (1 GiB, time cost 9). Even
with a key file that costs 4 to 6 s per volume at every unlock, because the
KDF runs on the key file too. A key file is already high entropy, so the KDF
adds nothing there.

Fix: add a second slot with pbkdf2 and one iteration count of 1000, and mark it
`prefer`. libcryptsetup tries `prefer` slots first. The old slot stays as a
fallback. The priority lives in the LUKS header, so crypttab and the initrd do
not change. The crypttab entries have no `keyslot=` option, which is required
for this to work: pinning a slot would skip the priority.

```sh
dev=/dev/disk/by-uuid/<uuid>
slot=<free slot number>   # see: cryptsetup luksDump $dev
sudo cryptsetup luksAddKey --key-file /etc/luks/home.key --key-slot $slot \
  --pbkdf pbkdf2 --pbkdf-force-iterations 1000 $dev /etc/luks/home.key
sudo cryptsetup config --priority prefer --key-slot $slot $dev
time sudo cryptsetup open --test-passphrase --key-file /etc/luks/home.key $dev
```

Applied 2026-10-16 as slot 2 on both volumes. A test unlock took about 0.04 s.
This is header state on the disks, not part of the Nix config. A reformat or a
new disk needs the recipe again.

### userspace: Home Manager gating the login screen

The Home Manager NixOS module orders `home-manager-<user>.service`
`Before=systemd-user-sessions.service`, which `greetd` waits for. At boot the
activation re-links an unchanged generation (about 4 s) and the greeter waits
for it. `flake-modules/hosts/ali-desktop/default.nix` now clears that
ordering with `lib.mkForce [ ]`. The greeter appears about 3.9 s earlier.
`graphical.target` timing is unchanged. Merged in #638 (`b06cb8e9`).

## Left alone

- **Loader, 2.3 s.** `modules/base/default.nix` sets the systemd-boot timeout
  with `lib.mkDefault 5`. Setting it to 0 was tried and reverted: holding a
  key at power-on did not show the menu, probably because the USB keyboard
  was not ready in time. 5 s stays; Enter skips it.
- **Firmware, 12.7 s.** BIOS side. Memory Context Restore could shorten
  memory training but is risky given the memory overclock history in the
  `ali-desktop-bios-update-memory-oc-saga` memory note.

## Verify after a reboot

```sh
systemd-analyze
systemd-analyze blame | grep -E 'cryptsetup|home-manager'
journalctl -b -o short-monotonic | grep -i 'TPM policy'
```

Expected: the `home1` and `home2` cryptsetup lines well under 1 s, no TPM
policy failure after a re-enrol, and `home-manager-ali.service` no longer in
the critical chain to the greeter. Compare against the baseline above.
