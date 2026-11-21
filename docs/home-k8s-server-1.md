# home-k8s-server-1

Bare-metal k3s agent for home-cluster-1.

## Hardware

| Part | Detail |
| --- | --- |
| Board | Compulab fitlet2, AMI BIOS FLT2.0.46.02.01 (2021-03-07) |
| CPU | Intel Celeron J3455 (Apollo Lake), 4 cores |
| RAM | 7.6 GiB |
| Disk | Kingston SA400 120 GB SATA SSD (`ata-KINGSTON_SA400M8120G_50026B7683D9077F`) |
| NICs | `eno1`, `enp1s0` (i211, igb); `enp3s0` (i210, igb). Only `eno1` is cabled. |
| TPM | Intel PTT (fTPM) on the SoC; a `J9A1 - TPM HDR` header for a discrete module |

On 2026-11-21 the OS saw no TPM. There was no ACPI TPM2 table, no SMBIOS
type-43 entry and no `/dev/tpm*` device. Another fitlet2 (BIOS .02.00) does
report an Intel fTPM, so PTT is most likely disabled in this unit's BIOS setup.

## Disk unlock

The root volume is LUKS2 (`crypted`) with LVM and ext4 on top. It unlocks in
one of three ways, tried in this order:

1. **TPM2.** crypttab carries `tpm2-device=auto` (from `systemIdentity.enable`).
   It works only after a TPM token has been enrolled (step 6 below).
2. **Passphrase at the console.**
3. **Passphrase over SSH in the initrd.** The initrd gets an address by DHCP
   on `eno1` and listens on port 2222:

   ```sh
   ssh -p 2222 root@192.168.1.251
   systemd-tty-ask-password-agent
   ```

   The initrd host key is generated at build time. After a nixpkgs bump it
   can change; clear the old one with `ssh-keygen -R "[192.168.1.251]:2222"`.

Until a TPM token is enrolled, every reboot needs step 2 or 3.

## Security trade-off

TPM unlock bound to PCR 7 protects the disk only when Secure Boot is
**enforced with your own keys**. PCR 7 records the Secure Boot state and keys.
With Secure Boot off, any USB stick booted on this box produces the same PCR 7
value, and the TPM releases the disk key to it. So:

- Enrol the TPM token only after Secure Boot is enforced (step 6 comes after
  step 5).
- Before that, the disk is protected only by the passphrase.

Do not bind PCR 15 (it is measured after unlock; see `modules/luksPCR15`).
Do not bind PCR 11. It changes with every kernel or initrd rebuild, so the
token stops unsealing; `docs/ali-desktop-boot-time.md` describes that failure.

## Runbook: TPM auto-unlock with Secure Boot

You need to be at the box (keyboard and monitor) for steps 1 and 5.

1. **Enable PTT.** In BIOS setup, enable Intel PTT / fTPM. After boot, check:

   ```sh
   ls /dev/tpmrm0
   sudo systemd-cryptenroll --tpm2-device=list
   ```

2. **Install** with `secureBootReady = false` (systemd-boot); see the Install
   section below.

3. **Create Secure Boot keys** on the box:

   ```sh
   sudo nix run nixpkgs#sbctl -- create-keys
   ```

   This writes `/var/lib/sbctl`. Back the directory up offline.

4. **Switch to Lanzaboote.** Set `secureBootReady = true` in
   `flake-modules/hosts/home-k8s-server-1/default.nix` and deploy. Check that
   everything is signed with `sudo nix run nixpkgs#sbctl -- verify`.

5. **Enrol the keys and enforce Secure Boot.** In BIOS setup, put Secure Boot
   in setup mode (clear the platform key), boot, then run:

   ```sh
   sudo nix run nixpkgs#sbctl -- enroll-keys --microsoft
   ```

   `--microsoft` keeps the Microsoft keys for option ROMs. Reboot, enable
   Secure Boot in the BIOS, and confirm with `bootctl status`
   (`Secure Boot: enabled (user)`).

6. **Enrol the TPM token** against PCR 7:

   ```sh
   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-main-luks
   ```

   It asks for the existing passphrase. The passphrase keyslot stays as the
   fallback. Reboot and confirm the disk unlocks with no prompt.

7. **Record PCR 15** (optional check):

   ```sh
   systemd-analyze pcrs 15 --json=short
   ```

   Put the `sha256` value in `modules.base.pcr15Value` and deploy. A mismatch
   is then logged at boot by the `check-pcrs` initrd unit.

Re-run step 6 (with `--wipe-slot=tpm2`) after changing Secure Boot keys or
BIOS Secure Boot settings, as that changes PCR 7.
