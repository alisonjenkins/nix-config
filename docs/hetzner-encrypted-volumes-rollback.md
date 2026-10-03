# Rolling back an encrypted volume migration

**You can go back to the old plain volume only while it still exists.** Once
`destroy-old-volume.sh --execute` has removed it, the way back is the backup,
not this page. That is the reason every volume gets a restore-tested backup
first. The plan is in [`specs/004-hetzner-encrypted-volumes/`](../specs/004-hetzner-encrypted-volumes/spec.md)
and the reasons in [ADR 0022](adr/0022-encrypt-hetzner-volumes.md).

The old volume stays safe because `retain-pv.sh` sets its PersistentVolume to
`Retain` before anything else happens. Deleting its claim then leaves the
volume at Hetzner.

Before you start, check what is left:

```sh
kubectl get pv | grep -E 'Retain|Released'      # the old volume's PV
hcloud volume list                              # the old volume at Hetzner
```

If either is gone, stop and restore from the backup instead.

## Databases (`shared-postgres`, `ente-db`)

The migration adds a second instance on the encrypted class, switches over, and
only later removes the old instance. Go back by making the old instance primary
again and dropping the new one. The `-rw` service name never changes, so the
applications need no change.

1. Run `check-no-call.sh`. It must print `calls=0`. A switchover interrupts chat
   for a few seconds.
2. Confirm the old instance is still running and has zero lag:
   `kubectl cnpg status CLUSTER -n NAMESPACE`.
3. Promote it: `kubectl cnpg promote CLUSTER OLD_INSTANCE -n NAMESPACE`.
4. Remove the new instance and its volume:
   `kubectl cnpg destroy CLUSTER NEW_INSTANCE -n NAMESPACE`.
5. Set `spec.storage.storageClass` back to `hcloud-volumes` in the cluster
   manifest, in a pull request, so Flux does not recreate the encrypted one.
6. Confirm the cluster reports `Cluster in healthy state` and the applications
   reconnected (Synapse and the authentication service for Matrix, Museum for photos).

The promote and destroy flags are not yet proven on CloudNativePG 1.30.1. They
are rehearsed on a scratch cluster first (research section 3). If a flag differs,
fix this page in the same pull request as the rehearsal.

If the old instance is already gone but its volume is still retained, do not
improvise. Restore from the backup into a new instance.

## File volumes (Matrix media, CouchDB, ntfy, Prometheus, Alertmanager, Grafana, game worlds)

These move by copying files from the old claim to a new encrypted claim. The old
claim is untouched until the end. Go back by pointing the workload at it again.

1. Scale the service to zero.
2. Point its manifest at the old claim name, in a pull request, and let Flux apply it.
3. Scale it up.
4. Run `verify.sh` for the service (health and functional parts) against the old claim.
5. Delete the new encrypted claim only after the service is confirmed healthy on the old one.

If the service is Matrix media, run `check-no-call.sh` first: scaling Synapse to
zero ends chat.

## What to record

Every step goes in `specs/004-hetzner-encrypted-volumes/evidence/`, with a UTC
time and the command output (the spec's FR-011). Never paste a passphrase, a
token or a test-account password.
