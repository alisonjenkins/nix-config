{ config, lib, pkgs, ... }:
let
  cfg = config.modules.docker;
in
{
  options.modules.docker = {
    enable = lib.mkEnableOption "Docker container runtime";

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

    storageDriver = lib.mkOption {
      type = lib.types.enum [ "overlay2" "btrfs" "zfs" "vfs" ];
      default = "overlay2";
      description = "Storage driver for container images and layers.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = cfg.autoPrune;
      daemon.settings.storage-driver = cfg.storageDriver;
    };

    hardware.nvidia-container-toolkit.enable = cfg.enableNvidia;

    boot.binfmt = lib.mkIf cfg.enableQemuBinfmt {
      emulatedSystems = cfg.binfmtEmulatedSystems;
      preferStaticEmulators = true;
    };

    environment.systemPackages = with pkgs; [
      docker-compose
    ];
  };
}
