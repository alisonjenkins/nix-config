# Restore the Minecraft world from a Velero backup (Hetzner)

The world (`minecraft-create-arkana-data`, namespace `minecraft`) is backed up by three Velero schedules, each backup quiesced
through RCON (`save-off`, `save-all flush`, then `save-on`) while the server runs:

| Schedule | When (UTC) | Kept |
|---|---|---|
| `velero-minecraft-2h` | every 2 hours | 3 days |
| `velero-minecraft-daily` | 04:30 | 90 days |
| `velero-minecraft-weekly` | Sunday 04:45 | 1 year |

A run while the server is down (0 replicas) backs up no volume, because no pod mounts it; the world only changes while the server
runs. A backup of the running server takes about 70 s for 6 GiB.

Tools come from the verify dev shell: `cd scripts/hetzner-volume-verify && nix develop`. Use `export KUBECONFIG=~/.kube/hetzner-cp.yaml`.

## 1. Pick a point

```sh
kubectl -n velero get backups.velero.io -l velero.io/schedule-name=velero-minecraft-daily \
  --sort-by=.status.completionTimestamp -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,DONE:.status.completionTimestamp
```

Take a `Completed` backup. The newest 2 hourly one for a grief noticed today, a daily or weekly one for an older point. A backup
that finished while the server was down has no volume data: check `kubectl -n velero get podvolumebackups -l velero.io/backup-name=<name>`
lists a `data` volume with a byte count.

## 2. Restore it next to the live world, never over it

Restore into a scratch namespace with its own new volume. The modifier replaces the server container with a `sleep` container and keeps
only the world volume, so a second server never starts and the live claim is never referenced.

```sh
BACKUP=<name from step 1>
kubectl -n velero apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata: {name: restore-minecraft-modifier, namespace: velero}
data:
  rules.yaml: |
    version: v1
    resourceModifierRules:
      - conditions: {groupResource: pods, resourceNameRegex: "^minecraft-.*"}
        patches:
          - operation: add
            path: /spec/containers
            value: '[{"name":"reader","image":"docker.io/library/busybox:1.37","command":["sleep","7200"],"resources":{"requests":{"cpu":"10m","memory":"8Mi"},"limits":{"memory":"128Mi"}},"volumeMounts":[{"name":"data","mountPath":"/data"}]}]'
          - operation: add
            path: /spec/volumes
            value: '[{"name":"data","persistentVolumeClaim":{"claimName":"minecraft-create-arkana-data"}}]'
          - operation: add
            path: /spec/serviceAccountName
            value: default
YAML
kubectl apply -f - <<YAML
apiVersion: velero.io/v1
kind: Restore
metadata: {name: restore-minecraft-$(date -u +%H%M%S), namespace: velero}
spec:
  backupName: $BACKUP
  namespaceMapping: {minecraft: restore-minecraft}
  includedResources: [pods, persistentvolumeclaims, persistentvolumes]
  restorePVs: true
  resourceModifier: {kind: configmap, name: restore-minecraft-modifier}
YAML
```

Straight after the restore starts (the claim appears within seconds), run the guard. It must say the scratch claim is bound to its own volume:

```sh
./check-restored-pvcs.sh restore-minecraft
```

If it names a volume that belongs to another claim, stop and delete the scratch namespace before anything runs.

Wait for the `Restore` to be `Completed` and the pod `Running` (the data copy of 6 GiB takes a few minutes).

## 3. Check it and compare

```sh
D=~/hetzner-encrypted-volumes/world-check-restored && mkdir -p "$D"
POD=$(kubectl -n restore-minecraft get pod -o name | head -1)
kubectl -n restore-minecraft exec "$POD" -- sh -c 'cd /data && find . -type d -name region -print0 | xargs -0 tar -cf -' | tar -xf - -C "$D"
./check-world.sh "$D/world"        # chunks_read=N unreadable=0, exit 0
```

`unreadable=0` and an exit code of 0 mean every chunk of every region file decompresses and parses. To get files back into the live world, copy them
from the scratch pod with the same `tar` pipe into a stopped server's volume (scale `minecraft` to 0 first, take a fresh backup, then write).

## 4. Clean up

```sh
kubectl delete ns restore-minecraft
kubectl -n velero delete restores.velero.io --all-namespaces -l velero.io/restore-name 2>/dev/null; kubectl -n velero delete cm restore-minecraft-modifier
rm -rf "$D"
```

The scratch volume has reclaim policy `Delete` and goes with its claim. Do not delete a `Restore` that is still `InProgress`: it keeps its
finalizers and blocks every later restore until they are removed by hand.

## Notes

- The pre-hook needs the API server to reach the game node's kubelet. That depends on the k3s server flag in
  [ADR 0026](adr/0026-hetzner-worker-node-networking.md); if backups end `PartiallyFailed` with `error dialing backend … x509`, check it first.
- A fresh game node's pod network can be stuck (same ADR). If the world pod stays `ContainerCreating` on `MountVolume.MountDevice … connection refused`, the
  watchdog restarts the Cilium agent within about 4 minutes; do not recycle the node.
- Verified 2026-10-05: backup of the running world 69 s, restore of 6,198,378,481 bytes, `check-world.sh` 178,391 chunks, 0 unreadable
  (`specs/004-hetzner-encrypted-volumes/evidence/backups.md`).
