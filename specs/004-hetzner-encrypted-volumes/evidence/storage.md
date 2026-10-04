# Encrypted storage class evidence (T022 to T027)

## T022, T023: the class exists (2026-10-04T05:15Z)

home-cluster PR 1562 merged 2026-10-04T05:14:58Z. Flux upgraded `hcloud-csi` to release 6 (chart 2.23.0).

```text
hcloud-volumes (default)   csi.hetzner.cloud   Delete   WaitForFirstConsumer   true
hcloud-volumes-encrypted   csi.hetzner.cloud   Delete   WaitForFirstConsumer   true
```

`hcloud-volumes-encrypted` parameters: `csi.storage.k8s.io/node-publish-secret-name: hcloud-volume-passphrase`
and `-namespace: kube-system`. Only `hcloud-volumes` is the default. The CSI controller and node pods did not restart
(restart counts unchanged, last restart 7 days ago).

Still to prove: T024 (a volume on the class is really encrypted), T025 (missing Secret), T026 (online resize).

## T024: a volume on the encrypted class is really encrypted (2026-10-04T05:24Z to 05:29Z)

Owner approved the test and the root access. Namespace `enc-test`, one 1 GiB claim on `hcloud-volumes-encrypted` and one
on `hcloud-volumes` (the control), each with a pod that wrote a known marker file. Hetzner's smallest volume is 10 GiB, so
both PVs show `10Gi`. Node root access was a `kubectl debug node/hetzner-k8s-master-1 --profile=sysadmin` pod (the method
in `docs/hetzner-k3s-live-maintenance.md`; the master has no SSH), used only for read-only commands and deleted after.

| Check | Encrypted volume | Plain volume (control) |
|---|---|---|
| Mount source seen inside the pod | `/dev/mapper/scsi-0HC_Volume_107028377` (device-mapper, major 252) | `/dev/disk/by-id/scsi-0HC_Volume_107028383` (SCSI disk, major 8) |
| `lsblk` on the raw device | `crypto_LUKS`, with a `crypt` child holding the mount | `ext4` |
| `cryptsetup isLuks` / `status` | yes; active; LUKS1, `aes-xts-plain64`, 512 bit key | not applicable |
| ext4 magic at offset 1080 of the raw device | `00 00` (absent) | `53 ef` (present) |
| Marker text in the first 2 GiB of the raw device (direct read) | 0 hits | 1 hit |
| `verify.sh --checks encryption` (through `--node-exec`) | `verdict=verified` | `verdict=failed`, three reasons |
| Create to container running | 29 s (05:24:52 to 05:25:21) | 19 s (05:25:30 to 05:25:49) |

The first mount of the encrypted volume took 10 s longer, well inside the 1 minute allowed by spec US5 scenario 3. The
plain volume's 1 hit shows the raw search would have found plain text, so the 0 hits on the encrypted device are meaningful.

Cleanup: the debug pod was deleted, then namespace `enc-test`. Both PVs were removed (reclaim policy `Delete`) and no
`enc-test` PV remains. An older completed `node-debugger-…-wqdrj` pod (2 days old, not from this test) was left alone.
Afterwards both Postgres clusters were healthy, no pod was failing, and the master was at 76% memory.

Observation for the script: `verify.sh --storageclass` is an argument, so the encryption check compares that class's
Secret reference with `--secret`, not the class the volume was actually provisioned with. The device and mapping checks
still catch a plain volume (as above), so the gate is safe, but reading the class from the PV would be tighter.
