# Moving home-k8s-master-1 to its planned address

home-k8s-master-1 is the only k3s server of home-cluster-1. It lives at
`192.168.1.129` today. `lib/home-lan.nix` plans it at `192.168.1.30`, in the
k8s range (.30–.39). No `homeLan` host holds `.30` (`nix eval
.#lib.homeLan.moveBlockers` does not list it). The UniFi DHCP pool is
`.6–.239`, though, so a dynamic client could hold it. On 2026-11-21 nothing
answered ARP for `.30`. Check again just before step 6:

```bash
nc -zv -w3 192.168.1.30 22; ip neigh show 192.168.1.30
```

`nc` must fail and the neighbour entry must be `INCOMPLETE` or `FAILED`.

The move is safe only once nothing reaches master-1 by its old IP. Steps 1–5
get there. Each one is a deploy or a merge on its own, and the cluster keeps
working after each. Step 6 is the move itself.

## What reaches master-1 by address

| Consumer | How | After step |
| --- | --- | --- |
| home-k8s-server-1 k3s agent | `serverAddr`, now `home-k8s-master-1.lan` from `/etc/hosts` | 2 |
| Cilium agent and operator (`k8sServiceHost`, kube-proxy replacement) | hostNetwork pods; read the node's `/etc/hosts` | 3 |
| download-server-1 firewall (Prometheus scrapes, Jellyseerr WAF) | `k8sNodeIPs`: `ip` and `plannedIp` from `homeLan` at build time | 5 |
| Your kubeconfig | `server: https://192.168.1.129:6443` | 6 |
| deploy-rs | `home-k8s-master-1.lan`, resolved by the UDM; overridden with `--hostname` during the move | 6 |
| API server cert | `--tls-san` for `ip` and `plannedIp` from `homeLan` | 5 |
| UniFi reservation and `home-k8s-master-1.lan` DNS record | terraform `unifi/home-lan.json`, synced from `homeLan` | 6 |

`/etc/hosts` on master-1, home-k8s-server-1 and download-server-1 comes from
`modules.homeLanHosts`. It maps every live `homeLan` host to `<name>.lan` and
`<name>`, so these names resolve with no LAN DNS at all.

## Before you start

- All of steps 1–5 are done and the cluster is healthy:
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
kubectl -n kube-system run hosts-check --rm -i --restart=Never --pod-running-timeout=3m --image=docker.io/library/busybox:1.37 --overrides='{"apiVersion":"v1","spec":{"hostNetwork":true,"nodeName":"<node>"}}' -- sh -c 'grep home-k8s-master-1 /etc/hosts && nc -z -w2 home-k8s-master-1.lan 6443 && echo API_OK'
```

The `grep` must print the `192.168.1.129` line, and the command must end with
`API_OK`. Merge only when both nodes pass. Do not test with `ping`: the hosts
ignore all ICMP echo (`modules.base.enableICMPPing` is off), so it always
fails. On master-1 the `grep` also prints `127.0.0.2 home-k8s-master-1`, the
NixOS entry for its own hostname; that is expected.

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

### 5. Put both addresses in the cert and the firewall

Steps 1–4 were live on 2026-11-21: the cert carries `DNS:home-k8s-master-1.lan`,
server-1 joins by that name, Cilium uses it, and download-server-1 has the
`/etc/hosts` entry.

This step adds `192.168.1.30` to the API server cert while master-1 still
holds `.129`, and lets download-server-1's firewall accept the k8s nodes at
either address. It changes nothing else, so it can go out any time.

Deploying master-1 restarts k3s, because its flags change. The API is gone
for about a minute; workloads keep running.

```bash
deploy --skip-checks .#home-k8s-master-1
```

```bash
deploy --skip-checks .#download-server-1
```

Check the cert:

```bash
nix shell nixpkgs#openssl -c sh -c 'openssl s_client -connect 192.168.1.129:6443 </dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName'
```

The list must include both `IP Address:192.168.1.129` and
`IP Address:192.168.1.30`. If `.30` is missing after the restart, the k3s
dynamic cert did not pick up the new flag. Regenerate it on master-1:

```bash
kubectl -n kube-system delete secret k3s-serving
```

```bash
ssh home-k8s-master-1.lan 'sudo rm /var/lib/rancher/k3s/server/tls/dynamic-cert.json && sudo systemctl restart k3s'
```

### 6. Move the address

Do this in one sitting. The cluster API is down from the reboot until
master-1 is back at `.30`, about 2–5 minutes.

1. **Expect a short LAN DNS gap.** The LAN resolvers `.246` and `.247` are
   Cilium L2 LoadBalancer IPs. Cilium needs the API server to renew its L2
   announcement leases, so they may stop answering while master-1 reboots.
   Pointing DHCP DNS at download-server-1 (`192.168.1.132`) does not help:
   the DHCP DNS servers are managed in terraform (`unifi/networks.tf`), so a
   console change is reverted by the apply below, and clients only see a new
   DNS server when their 24 h lease renews.
2. **Merge the two move PRs.** nix-config `move-master-1-to-30` sets
   `home-k8s-master-1.ip = "192.168.1.30"`. terraform `move-master-1-to-30`
   carries the matching `unifi/home-lan.json`. Pull both `main` branches.
3. **UniFi reservation.** In `terraform/unifi`:

   ```bash
   just backup
   ```

   ```bash
   just plan
   ```

   The plan must show one in-place update,
   `unifi_client.fixed["home-k8s-master-1"]`, with `fixed_ip` going from
   `192.168.1.129` to `192.168.1.30`. Then:

   ```bash
   just apply
   ```

   master-1 keeps its `.129` lease until it reboots. The UDM's
   `home-k8s-master-1.lan` record may already say `.30`, which is why the
   deploy below names the old address.
4. **Deploy download-server-1 and home-k8s-server-1.** Their `/etc/hosts` now
   point the name at `.30`, so server-1's agent and Cilium lose the API server
   until master-1 is back. That is expected.

   ```bash
   deploy --skip-checks .#download-server-1
   ```

   ```bash
   deploy --skip-checks .#home-k8s-server-1
   ```

5. **Deploy home-k8s-master-1 for next boot, then reboot it.** `--boot` stops
   the new `/etc/hosts` from pointing master-1's own Cilium at `.30` before
   the host holds that address. `--hostname` reaches it at the old address.

   ```bash
   deploy --skip-checks --boot --hostname 192.168.1.129 .#home-k8s-master-1
   ```

   ```bash
   ssh 192.168.1.129 sudo systemctl reboot
   ```

6. **Verify** on master-1, once it answers at `192.168.1.30`:

   ```bash
   nc -zv 192.168.1.30 6443
   ```

   ```bash
   ssh 192.168.1.30 'ip -4 addr show enp1s0; sudo systemctl status k3s --no-pager | head -5'
   ```

   ```bash
   ssh 192.168.1.30 'sudo journalctl -u k3s -b --no-pager | grep -iE "etcd|member|peer" | tail -20'
   ```

   Repeat the cert check from step 5 against `192.168.1.30`. The list must
   include `IP Address:192.168.1.30`.

If k3s comes up healthy, go to step 7. If etcd will not start, see
[Fallback: etcd cluster reset](#fallback-etcd-cluster-reset).

### 7. Point your kubeconfig at the name and check the cluster

```bash
kubectl config set-cluster default --server=https://home-k8s-master-1.lan:6443
```

The name resolves through the UDM, and it is in the cert. Then:

```bash
kubectl get nodes -o wide
```

Both nodes must be `Ready`; master-1's `INTERNAL-IP` must be `192.168.1.30`.

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep -E 'Kubernetes|KubeProxyReplacement'
```

```bash
dig +short @192.168.1.246 home-k8s-master-1.lan
```

```bash
dig +short @192.168.1.247 example.com
```

`Kubernetes` must say `Ok`, and both resolvers must answer.

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

Before step 6.3 is applied, nothing has moved: do not merge the two move PRs.

After it, revert both move PRs, then in `terraform/unifi` run `just backup`
and `just apply` to put the reservation back on `.129`. Deploy
download-server-1 and home-k8s-server-1, then master-1 for next boot at the
address it holds now, and reboot it:

```bash
deploy --skip-checks --boot --hostname 192.168.1.30 .#home-k8s-master-1
```

```bash
ssh 192.168.1.30 sudo systemctl reboot
```

If etcd then fails on the old address, use the same cluster reset. Step 5
needs no rollback: its cert and firewall entries are valid at either address.
