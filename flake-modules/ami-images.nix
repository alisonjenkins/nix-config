{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;

  # VM-free AMI image builder using systemd-repart + UKI.
  # Replaces make-disk-image.nix (requires KVM) with a fakeroot/unshare approach.
  # Works on any host including cross-compilation and non-metal EC2 instances.
  # Imported directly into the host config (not via image.modules.amazon) because
  # the repart config references config.system.build.{toplevel,uki}.
  commonAmiModule = self + "/lib/amazon-repart-image.nix";

  # Shared AWS base server config (used by aws-base-server and aws-base-server-arm)
  awsBaseServerConfig = { modulesPath, lib, ... }: {
    imports = [
      (modulesPath + "/virtualisation/amazon-image.nix")
    ];

    modules.aws.enable = true;
    modules.locale.enable = true;

    modules.servers = {
      enable = true;
      openPrometheusFirewallPort = false;
    };

    networking.hostName = "aws-base-server";

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

  # Shared AWS K8s node config
  awsK8sNodeConfig = { modulesPath, lib, ... }: {
    imports = [
      (modulesPath + "/virtualisation/amazon-image.nix")
    ];

    modules.aws.enable = true;
    modules.locale.enable = true;

    modules.servers = {
      enable = true;
      openPrometheusFirewallPort = false;
    };

    networking.hostName = "aws-k8s-node";

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

  # Shared AWS Karpenter node config — pre-bakes k3s agent + awscli2 for fast boot.
  # At boot, cloud-init writes /etc/karpenter-node.conf with runtime values
  # (master endpoint, SSM token path, region). A NixOS systemd service reads
  # this config and starts the k3s agent — no downloads, no curl-to-shell.
  #
  # GHA runner pods mount the host's /nix/store and daemon socket so builds
  # can use pre-warmed store paths. trusted-users includes "*" because the
  # runner container UID is unpredictable and these nodes only run GHA workloads.
  awsKarpenterNodeConfig = { modulesPath, lib, pkgs, ... }: {
    imports = [
      (modulesPath + "/virtualisation/amazon-image.nix")
    ];

    modules.aws = {
      enable = true;
      # enableSSH defaults to false — SSM agent (from amazon-image.nix) is primary access.
      # Worker IAM role has ssm:UpdateInstanceInformation + Session Manager permissions.
    };
    modules.locale.enable = true;

    networking = {
      hostName = "aws-karpenter-node";
      firewall.enable = lib.mkForce false; # Cilium eBPF is the firewall
    };

    # GHA runner pods connect to the host nix-daemon via mounted socket.
    # Trust all users since the container UID varies and these nodes only
    # run ephemeral GHA workloads.
    nix.settings.trusted-users = [ "root" "*" ];

    # Enable live kernel patching (kpatch/livepatch) for patching without reboot
    # LIVEPATCH is only supported on x86_64 in mainline Linux
    boot.kernelPatches = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [{
      name = "livepatch";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        LIVEPATCH = yes;
      };
    }];

    boot.kernel.sysctl = {
      # Cilium Envoy: allow binding to privileged ports (80/443) for Gateway API hostNetwork mode
      "net.ipv4.ip_unprivileged_port_start" = 0;
      # LiveKit SFU (WebRTC media): increase UDP buffer sizes
      "net.core.rmem_max" = 5000000;
      "net.core.wmem_max" = 5000000;
    };

    environment.systemPackages = with pkgs; [
      awscli2
      btrfs-progs
      k3s
      nftables
      xfsprogs
    ] ++ lib.optionals stdenv.hostPlatform.isx86_64 [
      (callPackage (self + "/pkgs/kpatch") {})
    ];

    # Pre-populate containerd image store at build time.
    # Instead of placing tarballs in /var/lib/rancher/k3s/agent/images/ (which k3s
    # must import into containerd on every boot, taking ~4 min), we run containerd
    # at nix build time with the `native` snapshotter, import the images, and bake
    # the populated store directly into the AMI. k3s boots with images ready instantly.
    image.repart.partitions."10-root".contents =
      let
        prepullImages = builtins.fromJSON (builtins.readFile ./karpenter-prepull-images.json);
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

    # NixOS-native k3s agent bootstrap service.
    # Reads config from /etc/karpenter-node.conf (written by cloud-init userData).
    # Avoids the upstream get.k3s.io install script which creates its own systemd units
    # outside NixOS's declarative control.
    systemd.services.k3s-agent-bootstrap = {
      description = "K3s Agent Bootstrap (Karpenter node)";
      after = [ "network-online.target" "cloud-init.service" ];
      wants = [ "network-online.target" ];
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

        # IMDSv2 metadata
        IMDS_TOKEN=$(${pkgs.curl}/bin/curl -s -X PUT \
          "http://169.254.169.254/latest/api/token" \
          -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
        INSTANCE_ID=$(${pkgs.curl}/bin/curl -s \
          -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
          http://169.254.169.254/latest/meta-data/instance-id)
        AVAILABILITY_ZONE=$(${pkgs.curl}/bin/curl -s \
          -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
          http://169.254.169.254/latest/meta-data/placement/availability-zone)
        PRIVATE_IP=$(${pkgs.curl}/bin/curl -s \
          -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
          http://169.254.169.254/latest/meta-data/local-ipv4)

        # Fetch K3s token from SSM
        K3S_TOKEN=$(${pkgs.awscli2}/bin/aws ssm get-parameter \
          --name "$SSM_TOKEN_PATH" \
          --with-decryption --query 'Parameter.Value' --output text \
          --region "$AWS_REGION")

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
          --node-ip "$PRIVATE_IP" \
          --kubelet-arg="provider-id=aws:///$AVAILABILITY_ZONE/$INSTANCE_ID" \
          --node-label="topology.kubernetes.io/region=$AWS_REGION" \
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

  # Shared AWS nix builder config
  awsNixBuilderConfig = { modulesPath, lib, pkgs, inputs, ... }: {
    imports = [
      (modulesPath + "/virtualisation/amazon-image.nix")
    ];

    modules.aws = {
      enable = true;
      enableSSH = true;
      # "auto" sizes the VHD to fit the closure (~few GB); the actual 200 GB
      # disk is specified at EC2 launch via --block-device-mappings and
      # auto-grows at boot via cloud-init growpart.
      rootVolumeSize = "auto";
    };
    modules.locale.enable = true;

    networking.hostName = "aws-nix-builder";

    nix = {
      settings = {
        max-jobs = "auto";
        cores = 0;
        # Download tuning — EC2 instances have high bandwidth, use it
        http-connections = 128;
        max-substitution-jobs = 128;
        download-buffer-size = 134217728; # 128 MiB
        # Cache "not found" responses for 1h to avoid re-querying caches
        # that don't have a path (saves thousands of HTTP requests per build)
        narinfo-cache-negative-ttl = 3600;
        # Fail fast on slow/unresponsive caches
        connect-timeout = 5;
        stalled-download-timeout = 10;
        # If a substituter has narinfo but download fails, try others or build
        fallback = true;
        # Ordered by hit rate: nixcache.org (own cache) first, then
        # high-value community caches. Dropped nix-gaming, rust-overlay,
        # and lantian/attic — zero hits in recent builds, just narinfo overhead.
        extra-substituters = [
          "https://cache.nixcache.org"
          "https://nix-community.cachix.org"
          "https://cache.garnix.io"
        ];
        extra-trusted-public-keys = [
          "nixcache.org-1:fd7sIL2BDxZa68s/IqZ8kvDsxsjt3SV4mQKdROuPoak="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        ];
      };
      gc.options = lib.mkForce "--delete-older-than 7d";
    };

    environment.systemPackages = with pkgs; [
      curl
      git
      git-lfs
      htop
      inputs.niks3.packages.${stdenv.hostPlatform.system}.default
      jq
      vim
    ];

    security.sudo.wheelNeedsPassword = lib.mkForce false;

    # SSH key is injected at launch time via cloud-init user-data,
    # so it can be rotated without rebuilding the AMI.
    users.users.builder = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };

    system.stateVersion = "25.11";
  };

  # Central registry of AMI configurations
  amiConfigs = {
    aws-base-server = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        self.nixosModules.servers
        awsBaseServerConfig
      ];
      extraModules = [];
    };

    aws-base-server-arm = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        self.nixosModules.servers
        awsBaseServerConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "aws-base-server-arm";
      }];
    };

    aws-k8s-node = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        self.nixosModules.servers
        self.nixosModules.app-k8s-master
        awsK8sNodeConfig
      ];
      extraModules = [];
    };

    aws-k8s-node-arm = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        self.nixosModules.servers
        self.nixosModules.app-k8s-master
        awsK8sNodeConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "aws-k8s-node-arm";
      }];
    };

    aws-karpenter-node-amd64 = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        awsKarpenterNodeConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "aws-karpenter-node-amd64";
      }];
    };

    aws-karpenter-node-arm = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        awsKarpenterNodeConfig
      ];
      extraModules = [];
    };

    aws-nix-builder = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        awsNixBuilderConfig
      ];
      extraModules = [];
    };

    aws-nix-builder-arm = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        awsNixBuilderConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "aws-nix-builder-arm";
      }];
    };

    # Warmed Karpenter node AMIs — identical to the base karpenter-node AMIs
    # but with desktop/laptop NixOS config closures pre-populated in the Nix
    # store via system.extraDependencies. When GHA runner pods mount the host's
    # /nix/store, builds find these paths already present and skip downloading.
    aws-karpenter-node-amd64-gha = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        awsKarpenterNodeConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "aws-karpenter-node-amd64";
        system.extraDependencies = [
          self.nixosConfigurations.ali-desktop.config.system.build.toplevel
          self.nixosConfigurations.ali-framework-laptop.config.system.build.toplevel
          self.nixosConfigurations.ali-work-laptop.config.system.build.toplevel
        ];
      }];
    };

    aws-karpenter-node-arm-gha = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        awsKarpenterNodeConfig
      ];
      extraModules = [{
        system.extraDependencies = [
          self.nixosConfigurations.dev-vm.config.system.build.toplevel
        ];
      }];
    };
  };

  mkAmiSystem = _name: cfg:
    lib.nixosSystem {
      system = cfg.system;

      specialArgs = {
        username = "ali";
        inherit inputs outputs;
        system = cfg.system;
      };

      modules = cfg.hostModules ++ [
        commonAmiModule
      ] ++ cfg.extraModules;
    };

  amiSystems = lib.mapAttrs mkAmiSystem amiConfigs;
in
{
  flake.nixosConfigurations = amiSystems;

  perSystem = { system, ... }: {
    packages = lib.mapAttrs'
      (name: _: lib.nameValuePair "${name}-ami" amiSystems.${name}.config.system.build.amazonImage)
      (lib.filterAttrs (_: cfg: cfg.system == system) amiConfigs);
  };
}
