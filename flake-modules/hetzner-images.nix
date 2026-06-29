{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;

  # Hetzner repart image builder (raw format, no VHD conversion)
  commonHetznerModule = self + "/lib/hetzner-repart-image.nix";

  # Cilium CNI bootstrap (k3s helm-controller manifest) — written to the k3s
  # manifests dir by the server bootstrap so the CNI is up before Flux.
  ciliumBootstrapManifest = self + "/flake-modules/hetzner-cilium-bootstrap.yaml";

  # Cattle-replace self-heal logic — a standalone, unit-tested script (the same
  # file the `hetzner-node-heal` check exercises, so the test tracks reality, no
  # duplication [B30,V27]). The systemd unit below provides its PATH.
  healScript = self + "/lib/hetzner-node-heal.sh";

  # Shared Hetzner Karpenter node config
  hetznerKarpenterNodeConfig = { modulesPath, lib, pkgs, ... }: {
    imports = [
      (import ../lib/hetzner-node-services.nix { inherit pkgs lib ciliumBootstrapManifest healScript; })
    ];

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
    # 0600 not 0666: the post-build-hook runs as root, so a world-writable queue
    # only lets an unprivileged process (or a pod with hostPath) inject store paths.
    systemd.tmpfiles.rules = [ "f /var/tmp/niks3-queue 0600 root root -" ];

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

    # NB: journald persistence + size cap (Storage=persistent, SystemMaxUse) is
    # the single authoritative config in modules/hetzner/default.nix — k3s-state-
    # volume bind-mounts /var/log/journal onto the LUKS volume so those persistent
    # logs survive a cattle replace [B25].

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
