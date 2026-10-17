# 0045. Keep an extra fast keyslot on the home LUKS volumes

- Status: Accepted
- Date: 2026-10-16

## Context

`ali-desktop` took 42.3 s to boot, 13.8 s of it in the initrd. Two causes
were in the LUKS setup (details in [ali-desktop-boot-time.md](../ali-desktop-boot-time.md)):

- The home volumes `home1` and `home2` unlock from `/etc/luks/home.key`, but
  their only slot used argon2i (1 GiB, time cost 9). The KDF runs on the key
  file as well, so each unlock cost 4 to 6 s for no security gain: the key
  file is high entropy.
- The root TPM2 token binds PCR 11, which changes on every kernel or initrd
  rebuild, so unsealing fails and the boot waits for a typed passphrase.

## Decision

Add a pbkdf2 keyslot (1000 iterations) for `/etc/luks/home.key` to each home
volume and mark it `prefer` with `cryptsetup config --priority prefer`. Keep
the original slots. Do not add a `keyslot=` option to crypttab and do not
change the initrd.

The fast slot is the one crypttab reaches first, because libcryptsetup tries
`prefer` slots before `normal` ones. The argon2i slot still works if the fast
one is ever damaged or removed.

This is on-disk state, applied by hand on 2026-10-16 (slot 2 on both
volumes). The recipe is in the topic doc. It is not in the Nix config.

Re-enrol the root TPM2 token after a UKI change. A durable fix is not decided.

## Alternatives rejected

- **Re-key the home volumes with a cheaper KDF in place.** Removes the
  fallback. A bad `luksChangeKey` on a volume that holds data is not worth
  4 to 6 s a boot.
- **Pin `keyslot=` in crypttab.** Works, but couples the config to a slot
  number that lives in the disk header, and skips `prefer` for any other
  volume.
- **Lower the argon2i cost on the existing slot.** Needs a passphrase-based
  change of that slot and still leaves a costly slot first.
- **Declarative provisioning (a systemd unit that adds the slot).** The
  header is per-disk state, set once; a service that edits LUKS headers at
  boot is more risk than the one-off command.

## Consequences

- Anyone with `/etc/luks/home.key` can unlock the home volumes, same as
  before. A 1000-iteration pbkdf2 slot only weakens the case where that key
  file is brute forced, and a random key file has no useful search space.
- Reformatting or replacing a disk loses the fast slot. The recipe must be
  run again.
- `luksDump` now shows two slots per home volume; the lowest-priority one is
  the fallback.

## Evidence

- Slot 2 added on both volumes on 2026-10-16. `cryptsetup open
  --test-passphrase --key-file /etc/luks/home.key` took about 0.04 s, against
  4 to 6 s before.
- Baseline `systemd-analyze`: firmware 12.7 s, loader 2.3 s, kernel 0.8 s,
  initrd 13.8 s, userspace 12.7 s, total 42.3 s.
- Root token: `cryptsetup token export --token-id 1` showed `tpm2-pcrs: [11]`.
- Effect on a real boot is not measured yet; it needs a reboot.

## Revisit when

- A reboot still shows `home1` or `home2` cryptsetup lines of several
  seconds: the preferred slot is not being used.
- The root TPM2 token goes stale again and re-enrolling by hand becomes a
  habit worth automating (signed PCR 11 policy, or PCR 7 with Secure Boot
  on).
- A disk is reformatted or replaced.
