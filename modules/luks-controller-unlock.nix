{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.luks-controller-unlock;
in {
  imports = [
    inputs.luks-controller-unlock.nixosModules.default
  ];

  options.modules.luks-controller-unlock = {
    enable = mkEnableOption "controller-driven LUKS unlock UI in stage 1";

    extraKernelModules = mkOption {
      type = types.listOf types.str;
      default = [
        # Default Steam Deck / generic-AMD set. Override per-host if you
        # need an Intel iGPU or a Nouveau-driven Nvidia output. The
        # upstream module has a bigger default that covers everything;
        # the wrapper trims it down because Steam Deck only needs amdgpu.
        "amdgpu"
        "evdev"
        "hid"
        "hid_generic"
        "hid_steam"
        "xpad"
      ];
      description = ''
        Kernel modules added to the initrd for DRM and controller HID.
        The defaults match a Steam Deck (AMD GPU + Steam Controller via
        hid-steam). Override on hosts with different GPUs or controllers.
      '';
    };

    maskConsoleAgent = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Mask systemd-ask-password-console.service in the initrd so the
        controller UI is the only thing on screen at boot. Keyboard
        passphrase entry continues to work because systemd-cryptsetup
        reads the controller agent's reply on the same socket — but
        the duplicate kernel-tty prompt is suppressed.
      '';
    };

    debugLogToEsp = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/dev/disk/by-partlabel/ESP";
      description = ''
        Mount this device (FAT) at /boot-debug in the initrd and capture
        the agent's stdout+stderr there. The ESP is unencrypted, so the
        log is readable from any rescue env without the LUKS pass.
        Debug only.
      '';
    };
  };

  config = mkIf cfg.enable {
    boot.initrd.luks-controller-unlock = {
      enable = true;
      package = inputs.luks-controller-unlock.packages.${pkgs.stdenv.hostPlatform.system}.default;
      inherit (cfg) maskConsoleAgent extraKernelModules debugLogToEsp;
    };
  };
}
