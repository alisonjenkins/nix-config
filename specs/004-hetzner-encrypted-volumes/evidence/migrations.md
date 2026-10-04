# Migration run records

One section per volume. Times are UTC.

## `couchdb-data` -> `couchdb-data-enc` (T073, 2026-10-04)

| Step | Result |
|---|---|
| New claim `couchdb-data-enc` on `hcloud-volumes-encrypted` (home-cluster#1572) | merged, `Pending` (WaitForFirstConsumer) until the copy job mounted it |
| Pause GitOps (`flux suspend kustomization flux-system`), `couchdb` scaled to 0 | about 14:08Z; the pod was gone before the copy |
| `migrate-files.sh --execute --uid 5984 --gid 5984` | first run **failed**: a non-root `rsync -a` cannot set times on the claim root or on the root-owned `lost+found` (exit 23), and the script refused as designed. Fixed in nix-config#479 (`--omit-dir-times --exclude=/lost+found`); second run copied 10 files at 14:12:08Z |
| Manifests (path, size, sha256, owner) of both claims | **identical**, 10 files each, owner `5984:5984` throughout |
| Old PV `pvc-fe5eb7e8…` set to `Retain` (`retain-pv.sh`) | done before the switch |
| Switch (home-cluster#1573: Deployment mounts `couchdb-data-enc`, plain claim removed), Flux resumed | applied at about 14:13Z; downtime about 5 minutes |
| Health | new pod `Running` and ready on the encrypted claim |
| Functional | all four databases listed; `obsidianlivesync` holds 3,068 documents; a test database was created, a document written and read back, and the database deleted |
| Fresh backup `couchdb-enc-20261004t141409z` | `Completed`, no errors or warnings, 14:14:54Z |

One surprise: when Flux resumed, an old-template pod briefly started on the old claim (about 3 s before the new one) and was
terminated by the rollout. The data had already been copied and the old claim was no longer used afterwards.

**Open: the encryption verdict.** `verify.sh --checks encryption` needs read-only commands on the node (a root debug pod). The
attempt to create one was denied by the session's permission guard, so the check has not been run on the new volume
(`pvc-1a920b1e…`, Hetzner volume 107030571). Until it passes, `destroy-old-volume.sh` will not remove the old volume (it needs a
`verified` verdict). The old volume (Hetzner id 106201840, PV `pvc-fe5eb7e8…`, `Released`, `Retain`) is untouched and is the way back.
The 24 hour limit of SC-007 runs from the switch (about 14:13Z): run the node check and destroy the old volume before then.
