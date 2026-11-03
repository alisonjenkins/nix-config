{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.wifi-sleep-reload;
  stateDir = "/run/wifi-sleep-reload";
  marker = "${stateDir}/unloaded";
in {
  options.services.wifi-sleep-reload = {
    enable = mkEnableOption ''
      Wi-Fi driver reload across sleep.

      MediaTek mt7921e (MT7921/MT7922) Wi-Fi comes back from s2idle or
      hibernate in a broken state (firmware "Message ... timeout",
      pci_pm_restore -110; afterwards SAE auth succeeds but the EAPOL 4-way
      handshake times out and latency is hundreds of ms) and only reloading the
      driver fixes it, so this unloads the driver before sleep and loads it
      again on resume. The link is already dropped by iwd before suspend, so the
      reload costs no extra reconnect.
    '';

    kernelModule = mkOption {
      type = types.str;
      default = "mt7921e";
      description = "Wi-Fi driver module to unload before sleep and reload on resume.";
    };

    unloadTimeoutSeconds = mkOption {
      type = types.ints.positive;
      default = 15;
      description = ''
        Timeout for unloading the driver before sleep. modprobe -r has been
        reported to hang on this driver (kernel bugzilla 217415), so the unload
        is bounded and sleep proceeds anyway if it times out.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.wifi-pre-sleep = {
      description = "Unload Wi-Fi driver before sleep";
      before = ["sleep.target"];
      wantedBy = ["sleep.target"];

      serviceConfig = {
        Type = "oneshot";
        # timeout cannot kill a modprobe stuck in the kernel, so systemd stops waiting too.
        TimeoutStartSec = cfg.unloadTimeoutSeconds + 5;
        ExecStart = pkgs.writeShellScript "wifi-pre-sleep" ''
          set -u

          ${pkgs.coreutils}/bin/mkdir -p ${stateDir}
          ${pkgs.coreutils}/bin/rm -f "${marker}"

          if [ ! -e "/sys/module/${cfg.kernelModule}" ]; then
            echo "wifi-sleep-reload: ${cfg.kernelModule} not loaded, nothing to unload"
            exit 0
          fi

          if ${pkgs.coreutils}/bin/timeout ${toString cfg.unloadTimeoutSeconds} ${pkgs.kmod}/bin/modprobe -r ${cfg.kernelModule}; then
            ${pkgs.coreutils}/bin/touch "${marker}"
            echo "wifi-sleep-reload: unloaded ${cfg.kernelModule}"
          else
            rc=$?
            echo "wifi-sleep-reload: failed to unload ${cfg.kernelModule} (exit $rc), sleeping with it loaded" >&2
            exit 0
          fi
        '';
      };
    };

    systemd.services.wifi-post-resume = {
      description = "Reload Wi-Fi driver after resume";
      after = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
        "suspend-then-hibernate.target"
      ];
      wantedBy = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
        "suspend-then-hibernate.target"
      ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "wifi-post-resume" ''
          set -u

          if [ -e "${marker}" ] || [ ! -e "/sys/module/${cfg.kernelModule}" ]; then
            ${pkgs.coreutils}/bin/rm -f "${marker}"
            if ${pkgs.kmod}/bin/modprobe ${cfg.kernelModule}; then
              echo "wifi-sleep-reload: loaded ${cfg.kernelModule}"
            else
              rc=$?
              echo "wifi-sleep-reload: failed to load ${cfg.kernelModule} (exit $rc)" >&2
              exit 1
            fi
          else
            ${pkgs.coreutils}/bin/rm -f "${marker}"
            echo "wifi-sleep-reload: ${cfg.kernelModule} stayed loaded across sleep, leaving it"
            exit 0
          fi
        '';
      };
    };
  };
}
