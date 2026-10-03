# Quickstart: prove each phase of the encryption work

How to check that each phase did what it should, in order. Each scenario states what it needs,
what to run, and what a pass looks like. Commands that change live state need the owner's
consent (plan, consent gates). The read-only ones do not.

All commands assume:

```sh
export KUBECONFIG=~/.kube/hetzner-cp.yaml
```

Times are ISO 8601 UTC. The verification script is `scripts/hetzner-volume-verify/verify.sh`
in nix-config, run inside its dev shell. Its checks are defined in
[contracts/verification.md](contracts/verification.md). The volume list is in
[data-model.md](data-model.md).

## Phase A: prerequisites

**A1. The operator can reach the databases**

```sh
kubectl get clusters.postgresql.cnpg.io -A
```

Pass: `shared-postgres` and `ente-db` both show `Cluster in healthy state`. Before the fix,
`shared-postgres` shows `Instance Status Extraction Error: HTTP communication issue`.

**A2. The backup identities exist and are scoped**

```sh
cd ~/git/terraform/main && tofu plan
```

Pass: the plan adds only the two IRSA roles (Velero, database backups), their policies for the
`velero-hetzner/` and `cnpg-hetzner/` prefixes, and the bucket-policy exemption. It changes
nothing else.

**A2b. Web identity works for each new role**

1. Run a short-lived pod whose service account is annotated with the role.
2. From it, ask AWS who it is (`aws sts get-caller-identity`).

Pass: it reports the assumed role. Do it once for the Velero role, once for the database
backup role, and once for the node-agent service account. Fail: stop and ask, as the spec
requires. Do not fall back to a static key.

**A3. The passphrase and the repository password exist**

```sh
kubectl get secret -n kube-system <passphrase secret> -o jsonpath='{.data.encryption-passphrase}' | wc -c
```

Pass: a non-zero length. Both secrets also exist in the password manager. Never print the value.

## Phase B: prove the mechanisms

**B1. Every volume has a backup less than 24 hours old**

```sh
velero backup get
kubectl get backups.postgresql.cnpg.io -A
```

Pass: a completed backup for each volume in the inventory. For a volume whose service is
stopped, the backup is dated after the volume's last change (spec FR-015). Databases also show continuous
archiving (`kubectl cnpg status` reports a recent last archived WAL). The Velero pod and each
node-agent pod carry the injected token and role ARN.

**B1b. A long upload survives credential expiry**

Back up the largest volume with a deliberately short role session duration.

Pass: the backup completes, or fails in a way that tells us the session duration to set. Record
the figure and set it before the real schedules run.

**B2. Every backup restores**

For a volume: restore into a scratch namespace and compare.

```sh
velero restore create --from-backup <backup> --namespace-mappings <live-ns>:scratch-<name>
```

For a database: bootstrap a scratch `Cluster` from the backup, with no backup section of its
own. Then run the comparison.

Pass: file and row comparisons match. The scratch namespace is deleted afterwards.

**B3. The encrypted class encrypts**

1. Create the Secret and the encrypted StorageClass, non-default.
2. Create a small volume and a pod that mounts it.
3. Run `verify.sh` part 0 against it.

Pass: the device shows `crypto_LUKS` and an active `crypt` mapping. The first mount completes
within 1 minute of a plain volume's (spec US5).

**B4. A missing passphrase never gives a silent plain volume**

1. Make the passphrase Secret unavailable in a scratch setup.
2. Create a volume on the encrypted class.

Pass: either the pod fails to start, or the verification fails part 0. A volume that mounts as
plain text and reports healthy is a failure of the whole approach. Stop and report.

**B5. The database switch rehearses cleanly**

On a scratch cluster in a scratch namespace: change the class, scale to 2, wait for zero lag,
promote, verify, destroy the old instance.

Pass: the webhook accepts the changed class. The switch interrupts connections for at most 2
minutes. Verification passes. Record whether any step differed from `research.md`.

**B6. A backup failure is reported**

Make a throwaway backup fail on purpose in a scratch namespace.

Pass: an alert fires and a notification reaches ntfy. A backup that is older than its limit
raises the stale alert. Clear the failure afterwards.

**B7. The way back works**

Before the first real move, rehearse the rollback in the runbook for a database (promote the
old instance again) and for a file volume (repoint to the old claim).

Pass: the service works on the old volume with its data intact, and nothing was removed.

**B8. The no-call check fails closed**

```sh
scripts/hetzner-volume-verify/check-no-call.sh
```

Pass: with a call running it exits non-zero and prints the participant count. With no call it
prints `calls=0` and exits 0. With the metrics endpoint unreachable it exits non-zero.

## Phase C: databases

For each database (Matrix and cache first, then photos), in a no-call window.

```sh
scripts/hetzner-volume-verify/verify.sh --volume shared-postgres-1 --new <new instance>
```

Pass: the output ends `verdict=verified`. Then a fresh backup of the new volume exists, and the
old volume is destroyed within 24 hours.

## Phase D: file volumes

For each volume in the inventory that is not a database.

1. Scale the service to zero.
2. Run the copy job.
3. Point the service at the new encrypted volume and scale it up.
4. Run `verify.sh --volume <name>`.

Pass: `verdict=verified`, a fresh Velero backup of the new volume, and the old volume gone
within 24 hours.

## Phase E: default and cleanup

**E1. New volumes are encrypted by default**

Create a small volume naming no class. Run `verify.sh` part 0.

Pass: encrypted. Existing workloads did not restart.

**E2. Nothing uses the plain class**

```sh
kubectl get pvc -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.storageClassName
kubectl get pv
```

Pass: no row shows `hcloud-volumes`, and no old plain volume exists at Hetzner.

**E3. The passphrase can be recovered from each saved copy**

In a scratch environment, mount a copy of an encrypted volume using only the repository copy,
then using only the password manager copy.

Pass: the data is readable both times.

**E3b. No long-lived storage key remains**

```sh
kubectl get secrets -A --no-headers | grep -i -E "aws|s3|restore"
```

Pass: no secret holds an AWS access key for backups, and the old restore user has no access
keys in AWS (spec SC-012).

**E4. Leftovers are listed**

Record every location that stays unencrypted (node root disks, `emptyDir` scratch space) in the
decision record, with the owner's acceptance (spec FR-013).

## Phase F: Minecraft world backups

These need the owner's consent for each step that touches the running game.

**F1. A running-world backup is consistent and does not disconnect anyone**

1. With a player connected, run a backup. The server saves and pauses writes, copies, and resumes.
2. Note whether the player sees a hitch or a disconnect.

Pass: no disconnect. Record the length of any hitch (spec FR-018, edge cases).

**F2. The end-of-session backup runs before scale-down**

Let the last player leave and wait for the idle timeout.

Pass: a backup dated after the last change exists, and the server then scales to zero. If the
backup is made to fail, the server still scales to zero after the limit, and the failure is
logged.

**F3. A past point restores next to the live world**

1. Build something recognisable, wait for a backup, then change it.
2. Restore that backup into a scratch namespace.
3. Run `scripts/hetzner-volume-verify/check-world.sh` on the restored copy, then open the
   restored world.

Pass: `check-world.sh` reports zero unreadable chunks, the world holds the earlier state, and
the live world is unchanged (SC-011). Repeat with the oldest tier available.

**F4. Tiers are kept**

```sh
velero backup get --selector <world backups>
```

Pass: points at 2 hour spacing for 3 days, daily to 90 days, weekly to a year, once enough time
has passed to show each tier.
