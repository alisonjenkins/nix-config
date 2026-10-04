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
