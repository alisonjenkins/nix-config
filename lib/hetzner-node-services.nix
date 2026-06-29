# Shared systemd service definitions for Hetzner Karpenter nodes.
# Used by both hetzner-images.nix (real image) and hetzner-tests.nix (VM test)
# so the test exercises the REAL unit scripts, not stale copies [B30,V27].
#
# Called as a plain Nix function (not a NixOS module function) so the caller
# can inject its own pkgs, lib, and the two store-path values.
{ pkgs, lib, ciliumBootstrapManifest, healScript }:
{
  systemd.services = {
    # Tailscale bootstrap service — brings up the Tailscale tunnel before k3s.
    # Auth key is provided via cloud-init userData in /etc/karpenter-node.conf.
    tailscale-bootstrap = {
      description = "Tailscale Bootstrap (Karpenter node)";
      after = [ "network-online.target" "cloud-init.service" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "k3s-agent-bootstrap.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        # Wait for cloud-init to write the config file
        for i in $(seq 1 60); do
          [ -f /etc/karpenter-node.conf ] && break
          sleep 2
        done
        source /etc/karpenter-node.conf

        # Skip if no Tailscale auth key provided
        if [ -z "''${TAILSCALE_AUTH_KEY:-}" ]; then
          echo "No TAILSCALE_AUTH_KEY set, skipping Tailscale bootstrap"
          exit 0
        fi

        # Bring up Tailscale. `hostname` is not in the stripped unit PATH (it's in
        # inetutils) → bare `$(hostname)` exits 127 [B27 class]. Read the kernel
        # hostname via a bash builtin redirection (no external `cat` either).
        ${pkgs.tailscale}/bin/tailscale up \
          --auth-key="$TAILSCALE_AUTH_KEY" \
          --hostname="$(< /proc/sys/kernel/hostname)"

        # Wait for Tailscale IP assignment
        for i in $(seq 1 30); do
          TS_IP=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null || true)
          [ -n "$TS_IP" ] && break
          sleep 2
        done

        echo "Tailscale IP: $TS_IP"
      '';
    };

    # k3s agent bootstrap service — joins the k3s cluster via Tailscale tunnel.
    # Reads config from /etc/karpenter-node.conf (written by cloud-init userData).
    k3s-agent-bootstrap = {
      description = "K3s Agent Bootstrap (Karpenter node)";
      after = [ "network-online.target" "cloud-init.service" "tailscale-bootstrap.service" ];
      wants = [ "network-online.target" ];
      requires = [ "tailscale-bootstrap.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "exec";
        Restart = "on-failure";
        RestartSec = "10s";
      };

      script = ''
        set -euo pipefail

        # Wait for cloud-init to write the config file
        for i in $(seq 1 60); do
          [ -f /etc/karpenter-node.conf ] && break
          sleep 2
        done
        source /etc/karpenter-node.conf

        # One image, two roles: only run the agent path on agent nodes. [V2]
        if [ "''${ROLE:-agent}" != "agent" ]; then
          echo "ROLE=''${ROLE:-agent}, not agent — skipping k3s-agent-bootstrap"
          exit 0
        fi

        # Get Hetzner metadata (YAML format, no auth needed). NB: instance-id is
        # NOT parsed — it was only for the dropped legacy self-set provider-id;
        # the hcloud CCM owns providerID=hcloud://<id> now [B17].
        METADATA=$(${pkgs.curl}/bin/curl -s http://169.254.169.254/hetzner/v1/metadata)
        LOCATION=$(echo "$METADATA" | ${pkgs.yq-go}/bin/yq '.region')

        # node-ip = PUBLIC: the hcloud CCM (networking.enabled=false) only knows
        # the server's public address; a private node-ip is rejected and providerID
        # never set [B10,B17]. Reaching the CP uses the private net via B7 + the
        # SERVER_ENDPOINT in the join config, independent of node-ip.
        NODE_IP=$(echo "$METADATA" | ${pkgs.yq-go}/bin/yq '.public-ipv4')

        # Wait for master reachability
        for i in $(seq 1 60); do
          ${pkgs.curl}/bin/curl -sk --max-time 3 \
            "https://$SERVER_ENDPOINT:6443/ping" && break
          sleep 2
        done

        # Run k3s agent (blocks — systemd manages the lifecycle)
        # cloud-provider=external: kubelet leaves providerID unset + adds the
        # uninitialized taint; hcloud CCM then sets providerID=hcloud://<id> and
        # untaints [I.ccm]. ⊥ self-set provider-id (CCM rejects non-hcloud:// — it
        # must own it; legacy hetzner:/// format broke node init).
        exec ${pkgs.k3s}/bin/k3s agent \
          --server "https://$SERVER_ENDPOINT:6443" \
          --token "$K3S_TOKEN" \
          --node-ip "$NODE_IP" \
          --kubelet-arg="cloud-provider=external" \
          --node-label="topology.kubernetes.io/region=$LOCATION" \
          --node-label="karpenter.sh/registered=true" \
          --kubelet-arg="kube-api-qps=100" \
          --kubelet-arg="kube-api-burst=200" \
          --kubelet-arg="event-qps=50" \
          --kubelet-arg="event-burst=100"
      '';
    };

    # --- control-plane (role=server) path -----------------------------
    #
    # Cattle master [V21]: root is the ephemeral snapshot; all k3s state lives
    # on a detachable LUKS volume mounted at /var/lib/rancher/k3s. Unlock is
    # post-boot SSH: the operator SSHes in and answers systemd-ask-password
    # (passphrase never on box). First-init is a one-time manual enrollment
    # (luksFormat + mkfs) — this service only OPENS an already-enrolled volume.

    k3s-state-volume = {
      description = "Unlock + mount the k3s state volume (role=server)";
      after = [ "network-online.target" "cloud-init.service" ];
      wants = [ "network-online.target" ];
      before = [ "k3s-server-bootstrap.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Allow the operator time to SSH in and answer the passphrase prompt.
        TimeoutStartSec = "infinity";
      };

      script = ''
        set -euo pipefail

        for i in $(seq 1 60); do
          [ -f /etc/karpenter-node.conf ] && break
          sleep 2
        done
        source /etc/karpenter-node.conf

        if [ "''${ROLE:-agent}" != "server" ]; then
          echo "ROLE=''${ROLE:-agent}, not server — skipping k3s-state-volume"
          exit 0
        fi

        # Auto-discover the attached Hetzner volume (only non-root block device).
        # On a cattle replace the tofu volume_attachment lands AFTER the server is
        # created, so the device can be absent for the first seconds of boot —
        # wait for it instead of failing immediately [B8].
        DEV=""
        for i in $(seq 1 60); do
          DEV=$(ls /dev/disk/by-id/scsi-0HC_Volume_* 2>/dev/null | head -1 || true)
          [ -n "$DEV" ] && break
          sleep 2
        done
        if [ -z "$DEV" ]; then
          echo "No Hetzner volume attached after 120s — cannot mount k3s state" >&2
          exit 1
        fi

        if ! ${pkgs.cryptsetup}/bin/cryptsetup isLuks "$DEV"; then
          echo "Volume $DEV is not LUKS — run one-time enrollment first (runbook)" >&2
          exit 1
        fi

        # Open via SSH-answerable prompt (passphrase never stored on the box).
        # --timeout=0: wait indefinitely for the operator; the default 90s expires
        # before an operator can SSH in and answer → unlock fails [B13].
        if [ ! -e /dev/mapper/k3s-state ]; then
          ${pkgs.systemd}/bin/systemd-ask-password --timeout=0 "Unlock k3s state volume:" \
            | ${pkgs.cryptsetup}/bin/cryptsetup luksOpen "$DEV" k3s-state -
        fi

        mkdir -p /var/lib/rancher/k3s
        # full path: bare `mount` is not in the unit PATH [B9].
        ${pkgs.util-linux}/bin/mountpoint -q /var/lib/rancher/k3s \
          || ${pkgs.util-linux}/bin/mount /dev/mapper/k3s-state /var/lib/rancher/k3s

        # Grow ext4 to the LUKS mapping (idempotent — no-op if already at size).
        # luksOpen maps the full backing device, so when the tofu volume is grown
        # [T24/B28] a fresh boot opens at the new size and this expands the fs —
        # no manual cryptsetup/resize2fs. Stops the containerd image store filling
        # the (previously 10G) state volume → DiskPressure → Museum evictions [B28].
        ${pkgs.e2fsprogs}/bin/resize2fs /dev/mapper/k3s-state 2>/dev/null || true

        # Persist Tailscale state on the LUKS volume so the node keeps its
        # Tailscale identity + IP across a cattle replace [B25]. Without this a
        # fresh VM re-registers under a new name/IP (master-1 -> master-1-1) and
        # the kubeconfig server (https://<ts-ip>:6443) breaks. Bind it here,
        # before tailscaled starts (tailscaled is ordered after this unit).
        mkdir -p /var/lib/rancher/k3s/tailscale /var/lib/tailscale
        ${pkgs.util-linux}/bin/mountpoint -q /var/lib/tailscale \
          || ${pkgs.util-linux}/bin/mount --bind /var/lib/rancher/k3s/tailscale /var/lib/tailscale

        # Persist the systemd journal on the LUKS volume so a dead node's logs
        # survive a VM nuke (cattle replace) — readable after the next boot
        # ["preserve logs across nukes", B25]. journald flushed early-boot logs to
        # the ephemeral root pre-unlock; re-open it on the persistent dir so the
        # operational logs (the ones that explain a death) land on the volume.
        # Size-capped via services.journald (SystemMaxUse) so it can't fill the vol.
        mkdir -p /var/lib/rancher/k3s/journal /var/log/journal
        # journald only accepts a persistent /var/log/journal owned root:systemd-
        # journal mode 2755 (setgid); without this it refuses to write there and
        # the cross-replace logs are lost [PR#154 review].
        ${pkgs.coreutils}/bin/chgrp systemd-journal /var/lib/rancher/k3s/journal 2>/dev/null || true
        ${pkgs.coreutils}/bin/chmod 2755 /var/lib/rancher/k3s/journal
        ${pkgs.util-linux}/bin/mountpoint -q /var/log/journal \
          || ${pkgs.util-linux}/bin/mount --bind /var/lib/rancher/k3s/journal /var/log/journal
        ${pkgs.systemd}/bin/systemctl restart systemd-journald 2>/dev/null || true
      '';
    };

    # tailscaled state lives on the LUKS volume (bound by k3s-state-volume) so the
    # Tailscale identity/IP is stable across a cattle replace [B25,V21]. Order it
    # after the volume is unlocked + bound. On agents k3s-state-volume is a no-op
    # that exits 0, so this ordering is harmless there (state stays on root).
    tailscaled = {
      after = [ "k3s-state-volume.service" ];
      requires = [ "k3s-state-volume.service" ];
    };

    # k3s server bootstrap — single master, SQLite (⊥ --cluster-init/etcd) [V21].
    # Cilium CNI, kube-proxy replacement, secrets-encryption [V4,V5]; tls-san =
    # floating IP + Tailscale [V3]. State dir provided by k3s-state-volume.
    k3s-server-bootstrap = {
      description = "K3s Server Bootstrap (cattle control-plane)";
      after = [ "network-online.target" "cloud-init.service" "tailscale-bootstrap.service" "k3s-state-volume.service" ];
      wants = [ "network-online.target" ];
      requires = [ "tailscale-bootstrap.service" "k3s-state-volume.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "exec";
        Restart = "on-failure";
        RestartSec = "10s";
      };

      script = ''
        set -euo pipefail

        for i in $(seq 1 60); do
          [ -f /etc/karpenter-node.conf ] && break
          sleep 2
        done
        source /etc/karpenter-node.conf

        if [ "''${ROLE:-agent}" != "server" ]; then
          echo "ROLE=''${ROLE:-agent}, not server — skipping k3s-server-bootstrap"
          exit 0
        fi

        # Require the encrypted state volume to be mounted before starting.
        ${pkgs.util-linux}/bin/mountpoint -q /var/lib/rancher/k3s

        # CNI bootstrap: drop Cilium (helm-controller) + Gateway API CRDs into the
        # k3s manifests dir so the CNI comes up before Flux [V4]. Idempotent.
        install -d /var/lib/rancher/k3s/server/manifests
        install -m644 ${ciliumBootstrapManifest} \
          /var/lib/rancher/k3s/server/manifests/cilium.yaml
        ${pkgs.curl}/bin/curl -fsSL --retry 5 \
          -o /var/lib/rancher/k3s/server/manifests/gateway-api-crds.yaml \
          https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml \
          || echo "WARN: Gateway API CRD fetch failed; Gateway inactive until present"

        # Tailscale IP is for tls-san/join only [V3]. node-ip MUST be a
        # hcloud-known address or the hcloud CCM rejects the node and never sets
        # providerID ("provided node ip ... not valid") [B10].
        TS_IP=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null || true)
        PUB_IP=$(${pkgs.curl}/bin/curl -s http://169.254.169.254/hetzner/v1/metadata \
          | ${pkgs.yq-go}/bin/yq '.public-ipv4')
        # Private IP is DHCP-only — Hetzner metadata does NOT expose it [B16], so
        # read it off the private NIC (10.0.0.0/8) once B7's DHCP has assigned it.
        # Wait up to 60s; the iface can lag network-online.target.
        PRIV_IP=""
        for _ in $(seq 1 30); do
          PRIV_IP=$(${pkgs.iproute2}/bin/ip -4 -o addr show 2>/dev/null \
            | ${pkgs.gawk}/bin/awk '$4 ~ /^10\.0\./ {print $4}' | ${pkgs.coreutils}/bin/cut -d/ -f1 | ${pkgs.coreutils}/bin/head -1)
          [ -n "$PRIV_IP" ] && break
          sleep 2
        done
        # node-ip = PUBLIC: the hcloud CCM runs networking.enabled=false so it only
        # knows the server's public address; a private node-ip is rejected ("node
        # address ... not valid") and providerID never set [B17]. The private IP is
        # used for tls-san (below), not node-ip.
        NODE_IP="$PUB_IP"

        # tls-san SHOULD include the private IP: it is the shared k8sServiceHost
        # [T10] that cilium + workers dial (https://<priv>:6443) — without it in
        # the cert, those TLS connections fail. The private NIC is attached at
        # server-create (stack-split) so the 60s wait above normally finds it; if
        # it is still absent we warn loudly + start anyway (failing closed here
        # would block the whole CP on a transient NIC lag, a worse outcome) [B16].
        PRIV_SAN=""
        if [ -n "$PRIV_IP" ]; then
          PRIV_SAN="--tls-san $PRIV_IP"
        else
          echo "WARN: no private (10.0.0.0/8) IP found — starting k3s WITHOUT the private tls-san; cilium/workers dialing the private k8sServiceHost will fail TLS until fixed [B16]" >&2
        fi

        # SQLite single-node control plane — NO --cluster-init (that is etcd).
        exec ${pkgs.k3s}/bin/k3s server \
          --token "$K3S_TOKEN" \
          --node-ip "$NODE_IP" \
          --tls-san "$FLOATING_IP" \
          ''${TS_IP:+--tls-san "$TS_IP"} \
          $PRIV_SAN \
          --flannel-backend=none \
          --disable-network-policy \
          --disable-kube-proxy \
          --disable=traefik \
          --disable=servicelb \
          --disable=local-storage \
          --disable-cloud-controller \
          --kubelet-arg=cloud-provider=external \
          --kube-controller-manager-arg=terminated-pod-gc-threshold=10 \
          --secrets-encryption \
          --cluster-cidr=10.42.0.0/16 \
          --service-cidr=10.43.0.0/16 \
          --write-kubeconfig-mode=0400
      '';
    };

    # Bind the Hetzner floating IP to eth0 on the CP so the Cilium Gateway
    # (hostNetwork Envoy, :443) is reachable through it [V13]. Hetzner routes the
    # floating IP to the server but the OS must accept it on an interface.
    floating-ip-bind = {
      description = "Bind Hetzner floating IP to eth0 (CP ingress) [V13]";
      after = [ "network-online.target" "cloud-init.service" "systemd-networkd.service" ];
      wants = [ "network-online.target" ];
      # PartOf systemd-networkd: a networkd restart flushes addresses (dropping
      # the floating IP); PartOf makes this unit restart with networkd and re-add
      # it, so the IP survives networkd restarts without manual re-binding [B25].
      partOf = [ "systemd-networkd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -euo pipefail
        for i in $(seq 1 60); do [ -f /etc/karpenter-node.conf ] && break; sleep 2; done
        source /etc/karpenter-node.conf
        if [ "''${ROLE:-agent}" != "server" ]; then
          echo "ROLE=''${ROLE:-agent}, not server — skipping floating-ip-bind"; exit 0
        fi
        [ -n "''${FLOATING_IP:-}" ] || { echo "no FLOATING_IP in conf"; exit 0; }
        ${pkgs.iproute2}/bin/ip -4 addr show eth0 | ${pkgs.gnugrep}/bin/grep -qw "$FLOATING_IP" \
          || ${pkgs.iproute2}/bin/ip addr add "$FLOATING_IP/32" dev eth0
        echo "floating IP $FLOATING_IP bound to eth0"
      '';
    };

    # Cattle-replace self-heal [B12,B20,B25]. The Node object persists on the LUKS
    # volume, so a replaced VM boots with the OLD providerID (hcloud://<old-id>)
    # and stale VolumeAttachments: CCM then can't find the server ("server not
    # found") and would delete the node, and CSI won't re-attach PVCs. On boot, if
    # the Node's providerID != this VM's hcloud id, drop the stale Node + its
    # VolumeAttachments and restart the server so it re-registers cleanly (k3s only
    # registers at startup). No-op on a normal reboot (providerID matches) or on
    # agents (role != server).
    k3s-node-heal = {
      description = "Heal stale Node/providerID + VolumeAttachments after a cattle replace [B12,B20]";
      after = [ "k3s-server-bootstrap.service" ];
      wants = [ "k3s-server-bootstrap.service" ];
      wantedBy = [ "multi-user.target" ];
      # Declare the script's deps on the unit PATH (NixOS strips defaults — this is
      # what the unit test mirrors). Kills the bare-command-127 class [B27].
      path = with pkgs; [ k3s curl yq-go gawk coreutils systemd ];
      # conf-wait (≤120s) + readyz-wait (≤300s) exceed systemd's 90s default →
      # set a generous timeout so the heal isn't killed before it runs [PR#155].
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = "600s"; };
      # Thin wrapper: role-guard, then run the standalone, unit-tested heal script.
      script = ''
        set -uo pipefail
        for i in $(seq 1 60); do [ -f /etc/karpenter-node.conf ] && break; sleep 2; done
        source /etc/karpenter-node.conf
        if [ "''${ROLE:-agent}" != "server" ]; then
          echo "ROLE=''${ROLE:-agent}, not server — skipping k3s-node-heal"; exit 0
        fi
        exec ${pkgs.bash}/bin/bash ${healScript}
      '';
    };
  };
}
