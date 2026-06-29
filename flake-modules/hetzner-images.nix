{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;

  # Hetzner repart image builder (raw format, no VHD conversion)
  commonHetznerModule = self + "/lib/hetzner-repart-image.nix";

  # Cilium CNI bootstrap (k3s helm-controller manifest) — written to the k3s
  # manifests dir by the server bootstrap so the CNI is up before Flux.
  ciliumBootstrapManifest = self + "/flake-modules/hetzner-cilium-bootstrap.yaml";

  # Shared Hetzner Karpenter node config
  hetznerKarpenterNodeConfig = { modulesPath, lib, pkgs, ... }: {
    modules.hetzner = {
      enable = true;
      # SSH enabled by default on Hetzner (primary access method)
    };
    modules.locale.enable = true;

    networking = {
      hostName = "hetzner-karpenter-node";
      firewall.enable = lib.mkForce false; # Cilium eBPF is the firewall
    };

    # GHA runner pods connect to the host nix-daemon via mounted socket.
    nix.settings.trusted-users = [ "root" "*" ];

    # Post-build-hook for niks3 binary cache push
    nix.settings.post-build-hook = pkgs.writeShellScript "niks3-post-build-hook" ''
      set -eu; set -f
      echo "$OUT_PATHS" | tr ' ' '\n' >> /var/tmp/niks3-queue
    '';
    systemd.tmpfiles.rules = [ "f /var/tmp/niks3-queue 0666 root root -" ];

    boot.kernel.sysctl = {
      # Cilium Envoy: allow binding to privileged ports (80/443) for Gateway API hostNetwork mode
      "net.ipv4.ip_unprivileged_port_start" = 0;
      # LiveKit SFU (WebRTC media): increase UDP buffer sizes
      "net.core.rmem_max" = 5000000;
      "net.core.wmem_max" = 5000000;
    };

    environment.systemPackages = with pkgs; [
      btrfs-progs
      cryptsetup
      k3s
      nftables
      tailscale
      xfsprogs
    ];

    # Enable Tailscale for cross-cloud networking
    services.tailscale.enable = true;

    # Persistent, size-capped journal. The journal dir is bind-mounted onto the
    # LUKS volume by k3s-state-volume so logs survive a cattle replace [B25]; cap
    # the size so it can't fill the (small) state volume.
    services.journald.extraConfig = ''
      Storage=persistent
      SystemMaxUse=500M
    '';

    # Post-quantum SSH key exchange [V12]. mlkem768x25519-sha256 needs
    # OpenSSH 9.9+; keep classical curve25519 as fallback for older clients.
    services.openssh.settings.KexAlgorithms = [
      "mlkem768x25519-sha256"
      "sntrup761x25519-sha512@openssh.com"
      "curve25519-sha256"
      "curve25519-sha256@libssh.org"
    ];

    # Pre-populate containerd image store at build time.
    # Reuses the same prepull image list as AWS but filters by architecture.
    # AWS-specific images (EBS/EFS CSI) are excluded via the hetzner-specific
    # prepull list if one exists, otherwise uses the shared list.
    image.repart.partitions."10-root".contents =
      let
        prepullFile = if builtins.pathExists ./hetzner-prepull-images.json
          then ./hetzner-prepull-images.json
          else ./karpenter-prepull-images.json;
        prepullImages = builtins.fromJSON (builtins.readFile prepullFile);
        arch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
        archImages = builtins.filter (img: img.arch == arch) prepullImages;
        tarballs = map (img: pkgs.dockerTools.pullImage {
          imageName = img.imageName;
          imageDigest = img.imageDigest;
          sha256 = img.hash;
          finalImageName = img.imageName;
          finalImageTag = img.imageTag;
        }) archImages;
        containerdStore = import (self + "/lib/containerd-prepopulate.nix") {
          inherit pkgs lib tarballs;
        };
      in {
        "/var/lib/rancher/k3s/agent/containerd".source = containerdStore;
      };

    # Tailscale bootstrap service — brings up the Tailscale tunnel before k3s.
    # Auth key is provided via cloud-init userData in /etc/karpenter-node.conf.
    systemd.services.tailscale-bootstrap = {
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

        # Bring up Tailscale
        ${pkgs.tailscale}/bin/tailscale up \
          --auth-key="$TAILSCALE_AUTH_KEY" \
          --hostname="$(hostname)"

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
    systemd.services.k3s-agent-bootstrap = {
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

        # Get Hetzner metadata (YAML format, no auth needed)
        METADATA=$(${pkgs.curl}/bin/curl -s http://169.254.169.254/hetzner/v1/metadata)
        SERVER_ID=$(echo "$METADATA" | ${pkgs.yq-go}/bin/yq '.instance-id')
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

    systemd.services.k3s-state-volume = {
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
        ${pkgs.util-linux}/bin/mountpoint -q /var/log/journal \
          || ${pkgs.util-linux}/bin/mount --bind /var/lib/rancher/k3s/journal /var/log/journal
        ${pkgs.systemd}/bin/systemctl restart systemd-journald 2>/dev/null || true
      '';
    };

    # tailscaled state lives on the LUKS volume (bound by k3s-state-volume) so the
    # Tailscale identity/IP is stable across a cattle replace [B25,V21]. Order it
    # after the volume is unlocked + bound. On agents k3s-state-volume is a no-op
    # that exits 0, so this ordering is harmless there (state stays on root).
    systemd.services.tailscaled = {
      after = [ "k3s-state-volume.service" ];
      requires = [ "k3s-state-volume.service" ];
    };

    # k3s server bootstrap — single master, SQLite (⊥ --cluster-init/etcd) [V21].
    # Cilium CNI, kube-proxy replacement, secrets-encryption [V4,V5]; tls-san =
    # floating IP + Tailscale [V3]. State dir provided by k3s-state-volume.
    systemd.services.k3s-server-bootstrap = {
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

        # tls-san MUST include the private IP: it is the shared k8sServiceHost
        # [T10] that cilium + workers dial (https://<priv>:6443) — without it in
        # the cert, TLS verification fails.
        PRIV_SAN=""
        [ -n "$PRIV_IP" ] && PRIV_SAN="--tls-san $PRIV_IP"

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
          --secrets-encryption \
          --cluster-cidr=10.42.0.0/16 \
          --service-cidr=10.43.0.0/16 \
          --write-kubeconfig-mode=0400
      '';
    };

    # Bind the Hetzner floating IP to eth0 on the CP so the Cilium Gateway
    # (hostNetwork Envoy, :443) is reachable through it [V13]. Hetzner routes the
    # floating IP to the server but the OS must accept it on an interface.
    systemd.services.floating-ip-bind = {
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
        ${pkgs.iproute2}/bin/ip -4 addr show eth0 | grep -qw "$FLOATING_IP" \
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
    systemd.services.k3s-node-heal = {
      description = "Heal stale Node/providerID + VolumeAttachments after a cattle replace [B12,B20]";
      after = [ "k3s-server-bootstrap.service" ];
      wants = [ "k3s-server-bootstrap.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -uo pipefail
        for i in $(seq 1 60); do [ -f /etc/karpenter-node.conf ] && break; sleep 2; done
        source /etc/karpenter-node.conf
        if [ "''${ROLE:-agent}" != "server" ]; then
          echo "ROLE=''${ROLE:-agent}, not server — skipping k3s-node-heal"; exit 0
        fi

        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        K="${pkgs.k3s}/bin/k3s kubectl"

        # Wait for the local API to be ready.
        for i in $(seq 1 60); do
          $K get --raw=/readyz >/dev/null 2>&1 && break
          sleep 5
        done

        # `hostname` is NOT in the systemd unit PATH on NixOS (it's in inetutils)
        # → the bare call exited 127 and the heal never ran [B25 self-heal bugfix].
        # Read the kernel hostname directly.
        NODE=$(cat /proc/sys/kernel/hostname)
        INSTANCE_ID=$(${pkgs.curl}/bin/curl -s http://169.254.169.254/hetzner/v1/metadata \
          | ${pkgs.yq-go}/bin/yq '.instance-id')
        WANT="hcloud://$INSTANCE_ID"
        HAVE=$($K get node "$NODE" -o jsonpath='{.spec.providerID}' 2>/dev/null || true)

        if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "null" ]; then
          echo "no instance-id from metadata — skipping heal"; exit 0
        fi
        if [ -z "$HAVE" ] || [ "$HAVE" = "$WANT" ]; then
          echo "providerID ok (have=''${HAVE:-none}) — no heal needed"; exit 0
        fi

        echo "stale providerID: have=$HAVE want=$WANT — healing"
        # Stale VolumeAttachments: detached at hcloud when the old VM died, but the
        # VA still claims attached → CSI won't re-attach [B20]. Delete those on this
        # node.
        for va in $($K get volumeattachments \
          -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers 2>/dev/null \
          | ${pkgs.gawk}/bin/awk -v n="$NODE" '$2==n {print $1}'); do
          echo "deleting stale VolumeAttachment $va"
          $K delete volumeattachment "$va" --wait=false || true
        done
        # Drop the stale Node so it re-registers fresh (CCM assigns the new
        # providerID by name). k3s only registers at startup → restart it [B12].
        $K delete node "$NODE" --wait=false || true
        echo "restarting k3s-server-bootstrap to re-register the node"
        ${pkgs.systemd}/bin/systemctl restart --no-block k3s-server-bootstrap.service || true
      '';
    };

    security.sudo.wheelNeedsPassword = lib.mkForce false;

    system.stateVersion = "25.11";

    users.users.ali = {
      isNormalUser = true;
      description = "Alison Jenkins";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        self.lib.sshKeys.primary
      ];
    };
  };

  hetznerConfigs = {
    hetzner-karpenter-node-amd64 = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.hetzner
        self.nixosModules.locale
        hetznerKarpenterNodeConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "hetzner-karpenter-node-amd64";
      }];
    };

    hetzner-karpenter-node-arm64 = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.hetzner
        self.nixosModules.locale
        hetznerKarpenterNodeConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "hetzner-karpenter-node-arm64";
      }];
    };
  };

  mkHetznerSystem = _name: cfg:
    lib.nixosSystem {
      system = cfg.system;

      specialArgs = {
        username = "ali";
        inherit inputs outputs;
        system = cfg.system;
      };

      modules = cfg.hostModules ++ [
        commonHetznerModule
      ] ++ cfg.extraModules;
    };

  hetznerSystems = lib.mapAttrs mkHetznerSystem hetznerConfigs;
in
{
  flake.nixosConfigurations = hetznerSystems;

  perSystem = { system, pkgs, ... }: {
    packages = (lib.mapAttrs'
      (name: _: lib.nameValuePair "${name}-image" hetznerSystems.${name}.config.system.build.hetznerImage)
      (lib.filterAttrs (_: cfg: cfg.system == system) hetznerConfigs))
    # Publish the amd64 image to Hetzner as a labelled snapshot. Idempotent by
    # convention: each run creates a new snapshot tagged purpose=k8s-node, and
    # the tofu CP/Karpenter side selects the most-recent match (T9 -> T6/T10).
    # Needs HCLOUD_TOKEN in the env (e.g. `op run -- nix run .#publish-...`).
    // lib.optionalAttrs (system == "x86_64-linux") {
      publish-hetzner-snapshot =
        let
          imagePkg = hetznerSystems."hetzner-karpenter-node-amd64".config.system.build.hetznerImage;
          version = hetznerSystems."hetzner-karpenter-node-amd64".config.system.nixos.version;
          # VM-free GRUB i386-pc install: boot.img -> MBR (patched with core LBA),
          # core.img -> bios_grub partition (patched blocklist). argv:
          # boot.img core.img raw bios_grub_lba
          biosInstallPy = pkgs.writeText "grub-bios-install.py" ''
            import struct, sys
            bootp, corep, rawp, lba = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
            boot = bytearray(open(bootp, "rb").read())
            core = bytearray(open(corep, "rb").read())
            core_sectors = (len(core) + 511) // 512
            struct.pack_into("<Q", boot, 0x5c, lba)
            struct.pack_into("<Q", core, 0x1f4, lba + 1)
            struct.pack_into("<H", core, 0x1fc, core_sectors - 1)
            struct.pack_into("<H", core, 0x1fe, 0x0820)
            with open(rawp, "r+b") as f:
                f.seek(0);         f.write(boot[:440])
                f.seek(lba * 512); f.write(core)
            print("GRUB BIOS installed: core %dB @ LBA %d" % (len(core), lba))
          '';
        in
        pkgs.writeShellApplication {
          name = "publish-hetzner-snapshot";
          runtimeInputs = [ pkgs.hcloud-upload-image pkgs.findutils pkgs.coreutils pkgs.util-linux pkgs.python3 ];
          text = ''
            : "''${HCLOUD_TOKEN:?Set HCLOUD_TOKEN (e.g. via op run)}"
            src=$(find ${imagePkg} -name '*.raw' | head -1)
            [ -n "$src" ] || { echo "no .raw found in ${imagePkg}" >&2; exit 1; }

            work=$(mktemp -d)
            trap 'rm -rf "$work"' EXIT
            cp "$src" "$work/image.raw"
            chmod +w "$work/image.raw"

            # Install GRUB i386-pc for SeaBIOS boot [V23,B3]. grub-bios-setup probes
            # host disks and fails in restricted envs, so place boot.img/core.img by
            # hand: boot.img -> MBR (patched with core's LBA), core.img -> bios_grub
            # partition (patched blocklist). Validated by qemu before first publish.
            lba=$(fdisk -l "$work/image.raw" | awk '/BIOS boot/{print $2}')
            [ -n "$lba" ] || { echo "no BIOS boot partition in image" >&2; exit 1; }
            python3 ${biosInstallPy} \
              ${imagePkg}/grub/boot.img ${imagePkg}/grub/core.img "$work/image.raw" "$lba"

            echo "Publishing as Hetzner snapshot (purpose=k8s-node)..."
            # NB: the "talos" tag in --description is load-bearing —
            # karpenter-provider-hetzner v1.0.0 resolves custom SNAPSHOTS only via
            # family=talos, which filters by `description contains "talos"` [B14].
            # family only selects the image; userData/cloud-init is passed
            # verbatim, so the NixOS image boots normally. Real image selection is
            # by the purpose=k8s-node label (HCloudNodeClass.imageSelector.selector).
            hcloud-upload-image upload \
              --image-path "$work/image.raw" \
              --architecture x86 \
              --location nbg1 \
              --description "talos-compat nixos-k8s-node amd64 ${version}" \
              --labels purpose=k8s-node,os=nixos,arch=amd64
          '';
        };
    };
  };
}
