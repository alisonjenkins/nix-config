# Moving home-k8s-master-1 to its planned address

home-k8s-master-1 is the only k3s server of home-cluster-1. It lives at
`192.168.1.129` today. `lib/home-lan.nix` plans it at `192.168.1.30`, in the
k8s range (.30–.39). Nothing else holds `.30` (`nix eval
.#lib.homeLan.moveBlockers` does not list it).

The move is safe only once nothing reaches master-1 by its old IP. Steps 1–4
get there. Each one is a deploy or a merge on its own, and the cluster keeps
working after each. Step 5 is the move itself.

## What reaches master-1 by address

| Consumer | How | After step |
| --- | --- | --- |
| home-k8s-server-1 k3s agent | `serverAddr`, now `home-k8s-master-1.lan` from `/etc/hosts` | 2 |
| Cilium agent and operator (`k8sServiceHost`, kube-proxy replacement) | hostNetwork pods; read the node's `/etc/hosts` | 3 |
| download-server-1 firewall (Prometheus scrapes, Jellyseerr WAF) | `k8sNodeIPs`, read from `homeLan` at build time | 5 (redeploy) |
| Your kubeconfig | `server: https://192.168.1.129:6443` | 6 |
| deploy-rs | `home-k8s-master-1.lan`, resolved by the UDM | 5 (UDM DNS) |

`/etc/hosts` on master-1, home-k8s-server-1 and download-server-1 comes from
`modules.homeLanHosts`. It maps every live `homeLan` host to `<name>.lan` and
`<name>`, so these names resolve with no LAN DNS at all.

## Before you start

- All of steps 1–4 are done and the cluster is healthy:
  `kubectl get nodes` shows both nodes `Ready`.
- Take an etcd snapshot on master-1 and copy it off the box:

  ```bash
  ssh home-k8s-master-1.lan sudo k3s etcd-snapshot save --name pre-ip-move
  ```

  ```bash
  ssh home-k8s-master-1.lan 'sudo ls -l /var/lib/rancher/k3s/server/db/snapshots/'
  ```

  ```bash
  scp 'home-k8s-master-1.lan:/var/lib/rancher/k3s/server/db/snapshots/pre-ip-move-*' ~/k3s-snapshots/
  ```

  The `scp` needs read access. If root owns the file, copy it to `/tmp` with
  `sudo cp` and `sudo chown ali` first.

## Steps

### 1. Deploy home-k8s-master-1

This adds the `home-k8s-master-1.lan` SAN to the API server cert and the
`/etc/hosts` entries.

```bash
deploy --skip-checks .#home-k8s-master-1
```

Check that the cert carries the name:

```bash
nix shell nixpkgs#openssl -c sh -c 'openssl s_client -connect 192.168.1.129:6443 </dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName'
```

The list must include `DNS:home-k8s-master-1.lan`. k3s adds new SANs on
restart; if the name is missing, run `sudo systemctl restart k3s` on master-1
and check again.

### 2. Deploy home-k8s-server-1

The agent now joins by `home-k8s-master-1.lan`.

```bash
deploy --skip-checks .#home-k8s-server-1
```

```bash
kubectl get node home-k8s-server-1
```

It must stay `Ready`. On the node, `journalctl -u k3s -n 50` must show no
x509 errors.

### 3. Merge the Cilium change

Branch `cilium-api-server-by-name` in home-cluster sets
`k8sServiceHost: home-k8s-master-1.lan`. Merge it only after steps 1 and 2,
then let Flux apply it.

First prove a hostNetwork pod resolves the name on **each** node. Replace
`<node>` with `home-k8s-master-1`, then `home-k8s-server-1`:

```bash
kubectl -n kube-system run hosts-check --rm -it --restart=Never --image=docker.io/library/busybox:1.37 --overrides='{"spec":{"hostNetwork":true,"nodeName":"<node>"}}' -- sh -c 'grep home-k8s-master-1 /etc/hosts && ping -c1 -W1 home-k8s-master-1.lan'
```

The `grep` must print the `192.168.1.129` line, and `ping` must resolve to
that address. Merge only when both nodes pass.

After Flux applies it:

```bash
kubectl -n kube-system rollout status ds/cilium
```

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep -E 'Kubernetes|KubeProxyReplacement'
```

`Kubernetes` must say `Ok`.

### 4. Deploy download-server-1

```bash
deploy --skip-checks .#download-server-1
```

This puts the `/etc/hosts` entries on it. Its firewall already reads the k8s
node IPs from `homeLan`.

### 5. Move the address

Do this in one sitting. The cluster API is down from the reboot until both
nodes are back.

1. **DNS fallback.** In the UniFi console, point the LAN's DHCP DNS server at
   download-server-1, `192.168.1.132`, for the duration of the move. Clients
   then keep DNS even if anything on the cluster side stalls. Revert it at
   the end.
2. **UniFi reservation.** Change the fixed IP for MAC `52:54:00:0a:29:2c`
   (home-k8s-master-1) from `192.168.1.129` to `192.168.1.30`.
3. **nix-config.** In `lib/home-lan.nix`, set
   `home-k8s-master-1.ip = "192.168.1.30"` (equal to `plannedIp`). Run
   `just check` and build the three hosts. Commit.
4. **Deploy download-server-1 and home-k8s-server-1** first. Their
   `/etc/hosts` now points the name at `.30`, so server-1's agent loses the
   API server until master-1 is back. That is expected.
5. **Deploy home-k8s-master-1**, then reboot it so it takes the new DHCP
   lease:

   ```bash
   ssh home-k8s-master-1.lan sudo systemctl reboot
   ```

6. **Verify** on master-1, once it answers at `192.168.1.30`:

   ```bash
   ssh 192.168.1.30 'ip -4 addr show enp1s0; sudo systemctl status k3s --no-pager | head -5'
   ```

   ```bash
   ssh 192.168.1.30 'sudo journalctl -u k3s -b --no-pager | grep -iE "etcd|member|peer" | tail -20'
   ```

   Then repeat the cert check from step 1 against `192.168.1.30`. The list
   must now include `IP Address:192.168.1.30`.

If k3s comes up healthy, go to step 6. If etcd will not start, see
[Fallback: etcd cluster reset](#fallback-etcd-cluster-reset).

### 6. Point your kubeconfig at the name

In `~/.kube/config`, change `server: https://192.168.1.129:6443` to
`server: https://home-k8s-master-1.lan:6443`. The name resolves through the
UDM, and it is in the cert. Then:

```bash
kubectl get nodes -o wide
```

Both nodes must be `Ready`; master-1's `INTERNAL-IP` must be `192.168.1.30`.

Finally revert the UniFi DHCP DNS server from step 5.1.

## Fallback: etcd cluster reset

master-1 runs embedded etcd as a single member (`--cluster-init`). The etcd
member records its peer URL with the node IP. If k3s does not rewrite it
after the move, etcd fails to start and the journal shows the old
`192.168.1.129:2380` peer URL. This is not verified on k3s v1.34, so be
ready for it.

`--cluster-reset` rewrites the membership to one member at the current
address and keeps the data:

```bash
ssh 192.168.1.30 sudo systemctl stop k3s
```

```bash
ssh 192.168.1.30 sudo k3s server --cluster-reset
```

Wait for `Managed etcd cluster membership has been reset, restart without
--cluster-reset flag now`. Then:

```bash
ssh 192.168.1.30 sudo systemctl start k3s
```

If the data itself is damaged, restore the snapshot instead. Copy it back to
`/var/lib/rancher/k3s/server/db/snapshots/` first if it is gone:

```bash
ssh 192.168.1.30 sudo systemctl stop k3s
```

```bash
ssh 192.168.1.30 sudo k3s server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<pre-ip-move-file>
```

```bash
ssh 192.168.1.30 sudo systemctl start k3s
```

## Rolling back

Before step 5.3 is deployed, nothing has moved: undo the UniFi reservation.

After it, revert the `lib/home-lan.nix` commit, put the reservation back to
`.129`, deploy the three hosts and reboot master-1. If etcd then fails on the
old address, use the same cluster reset.
