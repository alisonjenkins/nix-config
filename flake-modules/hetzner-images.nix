{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;

  # Hetzner repart image builder (raw format, no VHD conversion)
  commonHetznerModule = self + "/lib/hetzner-repart-image.nix";

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
      k3s
      nftables
      tailscale
      xfsprogs
    ];

    # Enable Tailscale for cross-cloud networking
    services.tailscale.enable = true;

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

        # Get Hetzner metadata (YAML format, no auth needed)
        METADATA=$(${pkgs.curl}/bin/curl -s http://169.254.169.254/hetzner/v1/metadata)
        SERVER_ID=$(echo "$METADATA" | ${pkgs.yq-go}/bin/yq '.instance-id')
        LOCATION=$(echo "$METADATA" | ${pkgs.yq-go}/bin/yq '.region')

        # Get the node IP — use Tailscale IP if available, otherwise private IP
        NODE_IP=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null || \
          echo "$METADATA" | ${pkgs.yq-go}/bin/yq '.private-networks[0].ip')

        # Wait for master reachability
        for i in $(seq 1 60); do
          ${pkgs.curl}/bin/curl -sk --max-time 3 \
            "https://$SERVER_ENDPOINT:6443/ping" && break
          sleep 2
        done

        # Run k3s agent (blocks — systemd manages the lifecycle)
        exec ${pkgs.k3s}/bin/k3s agent \
          --server "https://$SERVER_ENDPOINT:6443" \
          --token "$K3S_TOKEN" \
          --node-ip "$NODE_IP" \
          --kubelet-arg="provider-id=hetzner:///$LOCATION/$SERVER_ID" \
          --node-label="topology.kubernetes.io/region=$LOCATION" \
          --node-label="karpenter.sh/registered=true" \
          --kubelet-arg="kube-api-qps=100" \
          --kubelet-arg="kube-api-burst=200" \
          --kubelet-arg="event-qps=50" \
          --kubelet-arg="event-burst=100"
      '';
    };

    security.sudo.wheelNeedsPassword = lib.mkForce false;

    system.stateVersion = "25.11";

    users.users.ali = {
      isNormalUser = true;
      description = "Alison Jenkins";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
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

  perSystem = { system, ... }: {
    packages = lib.mapAttrs'
      (name: _: lib.nameValuePair "${name}-image" hetznerSystems.${name}.config.system.build.hetznerImage)
      (lib.filterAttrs (_: cfg: cfg.system == system) hetznerConfigs);
  };
}
