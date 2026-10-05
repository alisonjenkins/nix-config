# Hetzner master: apply k3s unit changes and compact the datastore without an outage

The master (`hetzner-k8s-master-1`) boots from a shared NixOS image, so changes to
`lib/hetzner-node-services.nix` only land when the server is replaced from a new
image (`tofu apply -replace=hcloud_server.cp`). On the single master that restarts
every pod. This runbook applies two such changes to the running node instead:

- `KillMode=process` / `Delegate=yes` on `k3s-server-bootstrap`, so restarting k3s
  leaves running pods (Matrix, the SFU, ingress) alone. Before this, any k3s
  restart killed every container on the node.
- `GOMEMLIMIT=1900MiB`, so the k3s process stops overshooting its ~1.6 GiB live
  heap to ~2.4 GiB and pushing the node into swap.

It then compacts the SQLite datastore if it is worth it.

There is no SSH to the master; everything goes through `kubectl debug node`.

## Before you start

- Pick a time with no Matrix call in progress. Pods keep running throughout, but
  the API server is down for ~1–2 minutes during the restart: nothing new can be
  scheduled, and anything that needs the API at that moment waits.
- Check the cluster is healthy and note the pods' restart counts:

  ```sh
  export KUBECONFIG=~/.kube/hetzner-cp.yaml
  kubectl get nodes
  kubectl get pods -A -o wide > /tmp/pods-before.txt
  ```

## 1. Open a root shell on the node

```sh
kubectl debug node/hetzner-k8s-master-1 -it --profile=sysadmin --image=busybox:1.37
# inside the debug pod:
chroot /host /run/current-system/sw/bin/bash
export PATH=/run/current-system/sw/bin
```

## 2. Apply the unit changes as a runtime drop-in (no restart yet)

`/run` is tmpfs, so this lasts until the next reboot or replacement, by which time
the image carries the same settings.

```sh
mkdir -p /run/systemd/system/k3s-server-bootstrap.service.d
cat > /run/systemd/system/k3s-server-bootstrap.service.d/50-live.conf <<'EOF'
[Service]
KillMode=process
Delegate=yes
Environment=GOMEMLIMIT=1900MiB
EOF
systemctl daemon-reload
systemctl show k3s-server-bootstrap -p KillMode -p Delegate -p Environment
```

Expect `KillMode=process`, `Delegate=yes` and `GOMEMLIMIT=1900MiB` in
`Environment`. **Do not continue unless `KillMode=process` shows**: with
`control-group`, the restart below kills every pod.

## 3. Restart k3s

Detach the restart from this shell, because the debug pod's own API connection
drops while k3s restarts:

```sh
systemd-run --on-active=5 --unit=k3s-live-restart systemctl restart k3s-server-bootstrap.service
exit   # leave the chroot and the debug pod
```

From your machine, wait for the API to answer again (~1–2 minutes), then check
that pods were not restarted:

```sh
kubectl get nodes
kubectl get pods -A -o wide > /tmp/pods-after.txt
diff <(awk '{print $1,$2,$5}' /tmp/pods-before.txt) <(awk '{print $1,$2,$5}' /tmp/pods-after.txt)
```

Only pods that talk to the API heavily (controllers holding leases) may show a
restart; Synapse, the SFU and the Envoy proxy should not.

## 4. Datastore: measure, then compact only if worthwhile

`k3s-datastore-maintenance` already compacts and vacuums automatically once
`state.db` plus WAL passes 2 GB. Below that, a manual VACUUM only helps if much of
the file is free pages. Measure first (read-only, safe with k3s running):

```sh
kubectl debug node/hetzner-k8s-master-1 -it --profile=sysadmin --image=busybox:1.37
chroot /host /run/current-system/sw/bin/bash
export PATH=/run/current-system/sw/bin
DB=/var/lib/rancher/k3s/server/db/state.db
ls -l $DB $DB-wal
nix-shell -p sqlite --run "sqlite3 -readonly $DB 'PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count; SELECT count(*), count(DISTINCT name) FROM kine;'"
```

- Free space ≈ `freelist_count × page_size`.
- Superseded revisions ≈ total rows minus distinct names.

If free pages plus superseded revisions are under ~200 MB, stop: the datastore is
healthy and a VACUUM is not worth an API outage.

Otherwise, with `KillMode=process` in effect (step 2), run the same procedure the
maintenance unit uses. Pods keep running; the API is down for its duration
(seconds to minutes at this size):

```sh
systemctl stop k3s-server-bootstrap.service
sqlite3 $DB ".backup '/var/tmp/k3s-datastore-premaintenance.db'"
sqlite3 $DB "PRAGMA wal_checkpoint(TRUNCATE);"
sqlite3 $DB "DELETE FROM kine WHERE id NOT IN (SELECT MAX(id) FROM kine GROUP BY name);"
sqlite3 $DB "VACUUM;"
ls -l $DB
systemctl start k3s-server-bootstrap.service
```

If `sqlite3` is not on the host PATH, prefix each command with
`nix-shell -p sqlite --run`. If anything fails, start k3s anyway
(`systemctl start k3s-server-bootstrap.service`); the safety copy is at
`/var/tmp/k3s-datastore-premaintenance.db`.

## 5. Afterwards

- Delete the debug pods: `kubectl get pods -A | grep node-debugger`, then delete them.
- After an hour, compare in Prometheus:
  - `go_memstats_heap_alloc_bytes{job="apiserver"}` should now peak around 1.9 GiB, not 2.4.
  - `rate(node_vmstat_pswpin[5m])` should be down.
  - Write latency (`apiserver_request_sli_duration_seconds` for POST, PUT, PATCH and DELETE) should be well under the 5 s lease deadline.
- The image carries the same settings from commits `fix(hetzner): keep pods running when k3s restarts` and
  `perf(hetzner): cap the k3s server's Go heap below the swap line`; the next server
  replacement makes them permanent.

# Make `kubectl logs`, `exec` and Velero hooks reach worker pods

Symptom: for a pod on a Karpenter worker (a game node), `kubectl logs` and `kubectl exec` fail with
`tls: failed to verify certificate: x509: certificate is valid for 127.0.0.1, ::1, <public ip>, not 10.0.1.1`,
and a Velero backup with an exec hook ends `PartiallyFailed` with `Error executing hook … error dialing backend`.

Cause: a worker's kubelet certificate is signed for its public `--node-ip` only (the hcloud CCM rejects a private one), the CCM
then adds the private `InternalIP`, and k3s makes the API server dial `InternalIP` first. The fix is the k3s server flag
`--kube-apiserver-arg=kubelet-preferred-address-types=Hostname,InternalIP,ExternalIP`: the node name is in both the worker and the master
certificates, and the k3s tunnel server maps a node-name dial to that node. (`ExternalIP` first would break the master: its certificate
covers only `10.0.1.10` and its name.) The image carries the flag from commit
`fix(hetzner): dial kubelets by node name so exec works on worker nodes`; until the master is replaced, apply it live.

Same safety rules as above: `KillMode=process` must show on `k3s-server-bootstrap` (step 2) or the restart kills every pod; pick a time with no
call; the API is down for 1 to 2 minutes while pods keep running.

```sh
export KUBECONFIG=~/.kube/hetzner-cp.yaml
kubectl get pods -A -o wide > /tmp/pods-before.txt
kubectl debug node/hetzner-k8s-master-1 -it --profile=sysadmin --image=busybox:1.37
# inside the debug pod:
chroot /host /run/current-system/sw/bin/bash
export PATH=/run/current-system/sw/bin
systemctl show k3s-server-bootstrap -p KillMode      # must print KillMode=process; if not, redo step 2 first
mkdir -p /etc/rancher/k3s/config.yaml.d
cat > /etc/rancher/k3s/config.yaml.d/50-kubelet-address-types.yaml <<'CONF'
kube-apiserver-arg:
  - "kubelet-preferred-address-types=Hostname,InternalIP,ExternalIP"
CONF
systemd-run --on-active=5 --unit=k3s-live-restart systemctl restart k3s-server-bootstrap.service
exit   # leave the chroot and the debug pod
```

Verify from your machine once the API answers:

```sh
kubectl get nodes
diff <(awk '{print $1,$2,$5}' /tmp/pods-before.txt) <(kubectl get pods -A -o wide --no-headers | awk '{print $1,$2,$5}')
kubectl -n monitoring logs prometheus-kube-prometheus-stack-prometheus-0 -c prometheus --tail=1   # master pods still work
kubectl -n minecraft scale deploy minecraft --replicas=1                                           # brings up a game node
kubectl -n minecraft logs deploy/minecraft --tail=3                                                # a worker pod now works
kubectl -n minecraft scale deploy minecraft --replicas=0
```

If a worker pod still fails, or master pods stop answering, remove `/etc/rancher/k3s/config.yaml.d/50-kubelet-address-types.yaml` and restart
`k3s-server-bootstrap` the same way. The file is on the ephemeral `/etc`, so a reboot also removes it, by which time the image has the flag.
