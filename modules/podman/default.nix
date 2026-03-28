{ config, lib, pkgs, ... }:
let
  cfg = config.modules.podman;
in
{
  options.modules.podman = {
    enable = lib.mkEnableOption "Podman container runtime";

    dockerCompat = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Docker CLI compatibility (podman-docker).";
    };

    dockerSocket = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Docker-compatible socket for tools that expect /var/run/docker.sock.";
    };

    autoPrune = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically prune unused images and containers.";
    };

    enableNvidia = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable NVIDIA Container Toolkit (CDI) support.";
    };

    enableQemuBinfmt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable QEMU binfmt_misc emulation for cross-architecture container builds (e.g. building arm64 Docker images on x86_64).";
    };

    binfmtEmulatedSystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "aarch64-linux" ];
      description = "List of systems to emulate via QEMU binfmt_misc.";
    };

    defaultNetwork = lib.mkOption {
      type = lib.types.enum [ "netavark" "cni" ];
      default = "netavark";
      description = "Default network backend.";
    };

    storageDriver = lib.mkOption {
      type = lib.types.enum [ "overlay" "btrfs" "zfs" "vfs" ];
      default = "overlay";
      description = "Storage driver for container images and layers.";
    };

    registries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "docker.io"
        "ghcr.io"
        "quay.io"
      ];
      description = "Unqualified search registries.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman = {
      enable = true;
      autoPrune.enable = cfg.autoPrune;
      dockerCompat = cfg.dockerCompat;
      dockerSocket.enable = cfg.dockerSocket;
      defaultNetwork.settings.dns_enabled = true;
    };

    virtualisation.containers.registries.search = cfg.registries;

    virtualisation.containers.storage.settings = {
      storage = {
        driver = cfg.storageDriver;
        graphroot = "/var/lib/containers/storage";
        runroot = "/run/containers/storage";
        options.overlay = lib.mkIf (cfg.storageDriver == "overlay") {
          mountopt = "nodev,metacopy=on";
        };
      };
    };

    hardware.nvidia-container-toolkit.enable = cfg.enableNvidia;

    boot.binfmt = lib.mkIf cfg.enableQemuBinfmt {
      emulatedSystems = cfg.binfmtEmulatedSystems;
      preferStaticEmulators = true;
    };

    environment.systemPackages = with pkgs; [
      podman-compose
      buildah
      skopeo
    ];

    # Allow rootless containers to bind to privileged ports (e.g. 80, 443)
    boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = lib.mkDefault 80;
  };
}
