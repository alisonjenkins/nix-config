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

## T025: what a wrong passphrase Secret does (2026-10-04T05:32Z to 05:35Z)

Two scratch StorageClasses in `enc-test`, each with a throwaway volume. The real Secret `kube-system/hcloud-volume-passphrase`
was never touched: its `resourceVersion` was 53972795 before and after.

| Case | Result |
|---|---|
| `node-publish-secret-name` points at a Secret that does not exist | **Safe.** The volume attached, but the pod stayed in `ContainerCreating` with `FailedMount … failed to find the secret enc-test-does-not-exist … not found`. Nothing was mounted. |
| The Secret exists but has no `encryption-passphrase` key (a wrong key name) | **Silent plain text.** The pod ran with no warning. Inside it, `/data` was an `ext4` mount on `/dev/disk/by-id/scsi-0HC_Volume_107028437` (major 8, the raw disk), not a device-mapper device. |

This matches the driver source (`mount.go:113`): an empty passphrase skips LUKS. A missing Secret is stopped by kubelet. A
Secret with the wrong key, or an empty value, is not. The hazard is the first mount of a new volume, when the driver formats it:
an existing LUKS volume mounted with an empty passphrase fails to mount, because the raw device is not ext4. So the guard has to
act when a claim is created. That is task T025a. `verify.sh` part 0 also catches such a volume after the fact (it fails a
plain device, as in T024).

## T026: online resize of an encrypted volume (2026-10-04T05:35Z to 05:37Z)

A 10 GiB claim on `hcloud-volumes-encrypted` held a 100 MiB random file and its SHA-256. The claim was patched to 20 Gi while
the pod kept it mounted.

- Patch at 05:36:29Z, claim capacity `20Gi` at 05:37:16Z (47 s). Events: `Resizing`, `FileSystemResizeRequired`,
  `FileSystemResizeSuccessful`. The pod did not restart (0 restarts).
- `df` inside the pod went from 9.7G to 19.6G. `sha256sum -c` of the file: OK. The marker file was intact.
- On the node (read-only): raw device 21474836480 bytes `crypto_LUKS`; active mapping 21472739328 bytes (20 GiB less the 2 MiB
  LUKS header), LUKS1 `aes-xts-plain64`, `ext4` inside. No driver secret was needed for the resize, as the source suggested.

Cleanup: namespace `enc-test`, both scratch classes and the scratch Secret deleted; no `enc-test` PV remains; both root debug
pods were deleted. Both Postgres clusters were healthy afterwards and the master was at 75% memory.

## T025a: the silent plain-text case is blocked (2026-10-04T05:40Z to 05:58Z)

home-cluster PR 1563 added the Kyverno policy `require-volume-passphrase` (`Enforce`) and a Role that lets Kyverno's admission
controller read exactly one Secret, `kube-system/hcloud-volume-passphrase`. The lookup runs only for claims of
`hcloud-volumes-encrypted`.

Before it went in, the same policy was tried on a scratch Secret, class and namespace (all deleted), with server-side dry-run claims:

| Case | Result |
|---|---|
| Secret has the wrong key | denied |
| Secret has a non-empty `encryption-passphrase` | admitted |
| Key present but empty | denied |
| Secret missing | denied, fail closed (`failed to check deny conditions … could not find the requested resource`) |
| Claim of a plain class while the Secret is missing | admitted: the guard cannot block ordinary claims |

After the merge (2026-10-04T05:58Z), against the real Secret: the policy is `Ready`; `kubectl auth can-i` shows Kyverno can read
`hcloud-volume-passphrase` and cannot read `hcloud`; a dry-run claim of `hcloud-volumes-encrypted` is admitted and so is one of
`hcloud-volumes`. No probe claim was created. The real Secret was never modified.

Gap, tracked in T067: a claim that names no class uses the default class, so once the default is switched to the encrypted class
the policy must cover that case too. Kyverno's resource filters also skip `kube-system`, so a claim made there is not checked;
no workload creates encrypted claims there.

## T027: storage proven (2026-10-04T05:52:24Z)

The encrypted class exists next to the unchanged default (T022, T023), a volume on it is LUKS with an active mapping and no
plain text in its raw bytes (T024), a missing Secret stops the mount and a wrong or empty passphrase is blocked at claim
creation (T025, T025a), and it resizes online with the data intact (T026). The 7 day clock starts when this and T049
(backups proven) are both done.

## T012, T013: password-manager copies (2026-10-04)

The owner approved creating both items. Each was created in the `Personal` vault by streaming the value from SOPS through `jq` into `op item create` on stdin
(never on a command line, in a file or in output), after checking no item with that title existed:

| 1Password item | Field | Length | SHA-256 prefix of the value |
|---|---|---|---|
| `Hetzner K8s - Volume Encryption Passphrase` | `password` | 64 | `669e024a2b2d53ff` |
| `Hetzner K8s - Velero Kopia Repository Password` | `password` | 64 | `e3790e01aabe4744` |

For each, the hash of the 1Password value, the SOPS file in git and the live Secret (`kube-system/hcloud-volume-passphrase`,
`velero/velero-repo-credentials`) are identical. Each item's notes say what it is, where else it lives, and that losing the passphrase loses the encrypted
volumes' data (and, for the repository password, makes every Velero backup unreadable). This closes FR-003 and the password-manager part of T012 and T013.

## T070, T071: the volume reads back with either copy of the passphrase (2026-10-04T12:55Z to 13:15Z)

SC-006. A throwaway 10 GiB claim on `hcloud-volumes-encrypted` in `enc-test` was written with a 4 MiB random file and its SHA-256
(`802280e1…`), its PV set to `Retain`, and the pod and claim deleted, which freed the volume at Hetzner. The old PV object was deleted
(its Secret reference is baked into it), then the volume was attached again twice through a static PV (same `volumeHandle`) whose
`nodePublishSecretRef` named a Secret built from one source each time:

| Drill | Secret built from | Result |
|---|---|---|
| T070 | `sops -d` of `secrets/hcloud-volume-passphrase.enc.yaml` in the repository | `sha256sum -c` OK, same hash |
| T071 | the password manager item "Hetzner K8s - Volume Encryption Passphrase" only | `sha256sum -c` OK, same hash |

Both Secrets were 64 bytes with the same SHA-256 prefix (`669e024a`), so the two copies are identical. No value was printed. The reader
pods mounted the claim read-only. Cleaned up: pods, claims, PVs, both drill Secrets and the namespace are deleted, and the orphaned
Hetzner volume (id 107030480, labelled `pvc-name: drill`) was deleted through the API after checking its name and labels.

The static claims were of the encrypted class, so the Kyverno claim guard ran on them and admitted them because
`kube-system/hcloud-volume-passphrase` is non-empty.
