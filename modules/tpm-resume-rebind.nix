{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.tpm-resume-rebind;
  sleepTargets = [
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];

  rebind = pkgs.writeShellApplication {
    name = "tpm-resume-rebind";
    runtimeInputs = [pkgs.coreutils pkgs.tpm2-tools pkgs.systemd];
    text = ''
      first_chip() {
        for c in /sys/class/tpmrm/tpmrm*; do
          if [ -e "$c" ]; then
            basename "$c"
            return 0
          fi
        done
      }

      probe() {
        for _ in 1 2 3; do
          if tpm2_getrandom -T device:/dev/tpmrm0 8 >/dev/null 2>&1; then
            return 0
          fi
          sleep 1
        done
        return 1
      }

      if probe; then
        echo "tpm-resume-rebind: TPM answers, nothing to do"
        exit 0
      fi

      old=$(first_chip)
      if [ -z "$old" ]; then
        echo "tpm-resume-rebind: no TPM chip registered, nothing to rebind" >&2
        exit 0
      fi
      dev=$(basename "$(readlink -f "/sys/class/tpmrm/$old/device")")
      drv=$(readlink -f "/sys/class/tpmrm/$old/device/driver")
      echo "tpm-resume-rebind: $old unresponsive, rebinding $dev on $drv"

      echo "$dev" > "$drv/unbind"
      sleep 1
      echo "$dev" > "$drv/bind"

      new=""
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        new=$(first_chip)
        [ -n "$new" ] && break
        sleep 0.5
      done
      if [ -z "$new" ]; then
        echo "tpm-resume-rebind: no TPM chip after rebinding $dev" >&2
        exit 1
      fi

      # consumers hardcode /dev/tpm0 and /dev/tpmrm0, but the old chip number may not be released.
      # A symlink left by an earlier rebind blocks devtmpfs from creating the real node when the
      # number is reused, so that case recreates the node by hand.
      point_node() {
        class=$1
        chip=$2
        if [ "$chip" != "''${class}0" ]; then
          ln -sfn "/dev/$chip" "/dev/''${class}0"
        elif [ -L "/dev/''${class}0" ]; then
          IFS=: read -r major minor < "/sys/class/$class/$chip/dev"
          rm -f "/dev/''${class}0"
          mknod -m 600 "/dev/''${class}0" c "$major" "$minor"
        fi
      }
      point_node tpmrm "$new"
      point_node tpm "tpm''${new#tpmrm}"

      if ! probe; then
        echo "tpm-resume-rebind: TPM still unresponsive after rebinding $dev" >&2
        exit 1
      fi
      echo "tpm-resume-rebind: $dev recovered as $new"

      systemctl reset-failed systemd-tpm2-setup.service libvirtd.service || true
      systemctl restart systemd-tpm2-setup.service
    '';
  };
in {
  options.services.tpm-resume-rebind.enable = mkEnableOption ''
    TPM driver rebind after resume.

    Hibernate power-cycles the TPM, so the resumed kernel's cached HMAC session
    null seed no longer matches ("tpm tpm0: NULL Seed name comparison failed")
    and the kernel disables the chip: every open fails with EIO until reboot,
    breaking systemd-tpm2-setup and libvirtd credentials. Unbinding and
    rebinding tpm_tis builds a fresh chip and null key, so HMAC stays enabled.
    Nothing is done when the TPM still answers
  '';

  config = mkIf cfg.enable {
    systemd.services.tpm-resume-rebind = {
      description = "Rebind TPM driver after resume if the TPM stopped answering";
      after = sleepTargets;
      wantedBy = sleepTargets;

      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe rebind;
      };
    };

    # The kernel only notices the stale null seed on its first HMAC-session TPM use, about 25 s
    # after resume, so the resume-time probe above usually still passes. The 2 s sleep lets the
    # kernel finish disabling the chip, which happens just after it logs the message.
    systemd.services.tpm-null-seed-watch = {
      description = "Rebind the TPM driver when the kernel reports a stale null seed";
      wantedBy = ["multi-user.target"];
      path = [pkgs.systemd pkgs.coreutils];

      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
        ExecStart = pkgs.writeShellScript "tpm-null-seed-watch" ''
          set -u
          journalctl --dmesg --follow --lines=0 --output=cat \
            --grep='NULL Seed name comparison failed' |
            while read -r line; do
              echo "tpm-null-seed-watch: kernel reported: $line"
              sleep 2
              systemctl start tpm-resume-rebind.service ||
                echo "tpm-null-seed-watch: tpm-resume-rebind failed" >&2
              sleep 30
            done
        '';
      };
    };
  };
}
