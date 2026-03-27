# Power management module for automatic AC/battery switching
{ config, lib, pkgs, ... }:

let
  cfg = config.modules.powerManagement;

  # Helper function fragment for error-reporting scripts
  # Each step logs its result and the script continues regardless
  runStepPreamble = ''
    FAILED_STEPS=()
    run_step() {
      local name="$1"
      shift
      if output=$("$@" 2>&1); then
        echo "  [OK] $name"
      else
        local rc=$?
        echo "  [FAIL] $name (exit $rc): $output" >&2
        FAILED_STEPS+=("$name (exit $rc)")
      fi
    }
    report_results() {
      if [ ''${#FAILED_STEPS[@]} -gt 0 ]; then
        echo "Power management: ''${#FAILED_STEPS[@]} step(s) failed:"
        for step in "''${FAILED_STEPS[@]}"; do
          echo "  - $step"
        done
      fi
    }
  '';

  # Script to apply battery power-saving settings
  powerSwitchBattery = pkgs.writeShellApplication {
    name = "power-switch-battery";
    runtimeInputs = with pkgs; [ coreutils findutils gnugrep iw power-profiles-daemon procps systemd sudo util-linux ];
    text = ''
      echo "Power management: switching to battery mode"
      ${runStepPreamble}

      ${lib.optionalString (cfg.onBattery.ppdProfile != null) ''
        run_step "power-profiles-daemon" powerprofilesctl set ${cfg.onBattery.ppdProfile}
      ''}

      ${lib.optionalString cfg.onBattery.wifiPowerSave ''
        run_step "wifi-power-save" iw dev wlan0 set power_save on
      ''}

      ${lib.optionalString cfg.onBattery.pciRuntimePM ''
        pci_runtime_pm() {
          for dev in /sys/bus/pci/devices/*/power/control; do
            echo auto > "$dev" 2>/dev/null
          done
        }
        run_step "pci-runtime-pm" pci_runtime_pm
      ''}

      ${lib.optionalString cfg.onBattery.usbAutosuspend ''
        usb_autosuspend() {
          for dev in /sys/bus/usb/devices/*/; do
            [ -f "$dev/power/control" ] || continue
            if [ -f "$dev/bDeviceClass" ] && grep -q "03" "$dev/bDeviceClass" 2>/dev/null; then continue; fi
            echo auto > "$dev/power/control" 2>/dev/null
          done
          echo 2 > /sys/module/usbcore/parameters/autosuspend
        }
        run_step "usb-autosuspend" usb_autosuspend
      ''}

      dirty_writeback_battery() {
        echo ${toString cfg.onBattery.dirtyWritebackCentisecs} > /proc/sys/vm/dirty_writeback_centisecs
      }
      run_step "dirty-writeback" dirty_writeback_battery

      ${lib.optionalString (config.services.scx.enable) ''
        scx_battery() {
          mkdir -p /run/power-management
          echo "SCX_FLAGS_OVERRIDE=${lib.escapeShellArgs cfg.onBattery.scxArgs}" > /run/power-management/scx.env
          systemctl restart scx.service
        }
        run_step "scx-scheduler" scx_battery
      ''}

      ${lib.optionalString (cfg.onBattery.noctaliaPerformanceMode && cfg.noctaliaUser != null) ''
        noctalia_battery() {
          if command -v noctalia-shell &>/dev/null; then
            sudo -u ${cfg.noctaliaUser} \
              DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u ${cfg.noctaliaUser})/bus" \
              XDG_RUNTIME_DIR="/run/user/$(id -u ${cfg.noctaliaUser})" \
              noctalia-shell ipc call powerProfile enableNoctaliaPerformance
          fi
        }
        run_step "noctalia-performance" noctalia_battery
      ''}

      ${lib.optionalString cfg.onBattery.throttleFossilize ''
        fossilize_throttle() {
          systemctl start fossilize-throttle.timer
          systemctl start fossilize-throttle.service
        }
        run_step "fossilize-throttle" fossilize_throttle
      ''}

      ${lib.optionalString cfg.onBattery.stopLact ''
        run_step "stop-lact" systemctl stop lact.service
      ''}

      ${lib.optionalString ((cfg.onBattery.displayMode != null || cfg.onBattery.enableVrr) && cfg.displayOutput != null && cfg.displayUser != null) ''
        display_battery() {
          local niri_sock
          niri_sock="$(find "/run/user/$(id -u "${cfg.displayUser}")" -maxdepth 1 -name 'niri.*.sock' -print -quit 2>/dev/null)"
          if [ -z "$niri_sock" ]; then
            echo "niri socket not found"
            return 1
          fi
          ${lib.optionalString (cfg.onBattery.displayMode != null) ''
            sudo -u ${cfg.displayUser} NIRI_SOCKET="$niri_sock" /run/current-system/sw/bin/niri msg output ${cfg.displayOutput} mode ${cfg.onBattery.displayMode}
          ''}
          ${lib.optionalString cfg.onBattery.enableVrr ''
            sudo -u ${cfg.displayUser} NIRI_SOCKET="$niri_sock" /run/current-system/sw/bin/niri msg output ${cfg.displayOutput} vrr on
          ''}
        }
        run_step "display-mode" display_battery
      ''}

      ${lib.optionalString (cfg.onBattery.kbdBacklightOff != null) ''
        kbd_backlight_off() {
          local current
          current=$(${pkgs.qmk_hid}/bin/qmk_hid --vid 32ac --pid ${cfg.onBattery.kbdBacklightOff} via --rgb-brightness 2>&1 | grep -oP '\d+')
          if [ -n "$current" ] && [ "$current" != "0" ]; then
            echo "$current" > /run/power-management/kbd-brightness-saved
          fi
          ${pkgs.qmk_hid}/bin/qmk_hid --vid 32ac --pid ${cfg.onBattery.kbdBacklightOff} via --rgb-brightness 0
        }
        run_step "kbd-backlight-off" kbd_backlight_off
      ''}

      ${lib.optionalString cfg.onBattery.bluetoothAutosuspend ''
        bt_autosuspend() {
          echo Y > /sys/module/btusb/parameters/enable_autosuspend
          for iface in /sys/bus/usb/drivers/btusb/*/; do
            [ -d "$iface/driver" ] || continue
            dev="$(dirname "$(realpath "$iface")")"
            echo auto > "$dev/power/control" 2>/dev/null
          done
        }
        run_step "bluetooth-autosuspend" bt_autosuspend
      ''}

      report_results
      echo "Power management: battery mode active"
    '';
  };

  # Script to apply AC performance settings
  powerSwitchAC = pkgs.writeShellApplication {
    name = "power-switch-ac";
    runtimeInputs = with pkgs; [ coreutils findutils gnugrep iw power-profiles-daemon procps systemd sudo util-linux ];
    text = ''
      echo "Power management: switching to AC mode"
      ${runStepPreamble}

      ${lib.optionalString (cfg.onAC.ppdProfile != null) ''
        run_step "power-profiles-daemon" powerprofilesctl set ${cfg.onAC.ppdProfile}
      ''}

      ${lib.optionalString cfg.onBattery.wifiPowerSave ''
        run_step "wifi-power-save" iw dev wlan0 set power_save off
      ''}

      dirty_writeback_ac() {
        echo ${toString cfg.onAC.dirtyWritebackCentisecs} > /proc/sys/vm/dirty_writeback_centisecs
      }
      run_step "dirty-writeback" dirty_writeback_ac

      ${lib.optionalString (config.services.scx.enable) ''
        scx_ac() {
          mkdir -p /run/power-management
          echo "SCX_FLAGS_OVERRIDE=${lib.escapeShellArgs cfg.onAC.scxArgs}" > /run/power-management/scx.env
          systemctl restart scx.service
        }
        run_step "scx-scheduler" scx_ac
      ''}

      ${lib.optionalString (cfg.onBattery.noctaliaPerformanceMode && cfg.noctaliaUser != null) ''
        noctalia_ac() {
          if command -v noctalia-shell &>/dev/null; then
            sudo -u ${cfg.noctaliaUser} \
              DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u ${cfg.noctaliaUser})/bus" \
              XDG_RUNTIME_DIR="/run/user/$(id -u ${cfg.noctaliaUser})" \
              noctalia-shell ipc call powerProfile disableNoctaliaPerformance
          fi
        }
        run_step "noctalia-performance" noctalia_ac
      ''}

      ${lib.optionalString cfg.onBattery.throttleFossilize ''
        fossilize_unthrottle() {
          systemctl stop fossilize-throttle.timer
          pkill -CONT -f fossilize_replay 2>/dev/null || true
        }
        run_step "fossilize-unthrottle" fossilize_unthrottle
      ''}

      ${lib.optionalString cfg.onBattery.stopLact ''
        run_step "start-lact" systemctl start lact.service
      ''}

      ${lib.optionalString ((cfg.onAC.displayMode != null || cfg.onBattery.enableVrr) && cfg.displayOutput != null && cfg.displayUser != null) ''
        display_ac() {
          local niri_sock
          niri_sock="$(find "/run/user/$(id -u "${cfg.displayUser}")" -maxdepth 1 -name 'niri.*.sock' -print -quit 2>/dev/null)"
          if [ -z "$niri_sock" ]; then
            echo "niri socket not found"
            return 1
          fi
          ${lib.optionalString (cfg.onAC.displayMode != null) ''
            sudo -u ${cfg.displayUser} NIRI_SOCKET="$niri_sock" /run/current-system/sw/bin/niri msg output ${cfg.displayOutput} mode ${cfg.onAC.displayMode}
          ''}
          ${lib.optionalString cfg.onBattery.enableVrr ''
            sudo -u ${cfg.displayUser} NIRI_SOCKET="$niri_sock" /run/current-system/sw/bin/niri msg output ${cfg.displayOutput} vrr off
          ''}
        }
        run_step "display-mode" display_ac
      ''}

      ${lib.optionalString (cfg.onBattery.kbdBacklightOff != null) ''
        kbd_backlight_restore() {
          local saved="13"
          if [ -f /run/power-management/kbd-brightness-saved ]; then
            saved=$(cat /run/power-management/kbd-brightness-saved)
          fi
          ${pkgs.qmk_hid}/bin/qmk_hid --vid 32ac --pid ${cfg.onBattery.kbdBacklightOff} via --rgb-brightness "$saved"
        }
        run_step "kbd-backlight-restore" kbd_backlight_restore
      ''}

      ${lib.optionalString cfg.onBattery.bluetoothAutosuspend ''
        bt_no_autosuspend() {
          echo N > /sys/module/btusb/parameters/enable_autosuspend
          for iface in /sys/bus/usb/drivers/btusb/*/; do
            [ -d "$iface/driver" ] || continue
            dev="$(dirname "$(realpath "$iface")")"
            echo on > "$dev/power/control" 2>/dev/null
          done
        }
        run_step "bluetooth-autosuspend-off" bt_no_autosuspend
      ''}

      report_results
      echo "Power management: AC mode active"
    '';
  };

  # Script to temporarily unthrottle fossilize (for game launches on battery)
  fossilizeUnthrottle = pkgs.writeShellApplication {
    name = "fossilize-unthrottle";
    runtimeInputs = with pkgs; [ coreutils procps systemd ];
    text = ''
      echo "Unthrottling fossilize_replay processes..."

      # Stop the throttle timer
      sudo systemctl stop fossilize-throttle.timer 2>/dev/null || true

      # Resume any stopped fossilize processes
      pkill -CONT -f fossilize_replay 2>/dev/null || true

      DURATION="''${1:-}"
      if [ -n "$DURATION" ]; then
        echo "Will re-enable throttling in $DURATION"
        systemd-run --on-active="$DURATION" --unit=fossilize-rethrottle \
          /bin/sh -c 'systemctl start fossilize-throttle.timer && systemctl start fossilize-throttle.service' 2>/dev/null || true
      else
        echo "Fossilize unthrottled until next AC/battery switch"
        echo "Usage: fossilize-unthrottle [duration] (e.g., 30m, 1h)"
      fi
    '';
  };
in
{
  options.modules.powerManagement = {
    enable = lib.mkEnableOption "automatic AC/battery power management switching";

    onBattery = {
      ppdProfile = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "power-saver" "balanced" "performance" ]);
        default = "power-saver";
        description = "power-profiles-daemon profile to set when on battery.";
      };

      scxArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Arguments for scx_lavd scheduler on battery. Empty list uses default energy-aware mode.";
      };

      wifiPowerSave = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable iwd WiFi power save on battery (adds 10-50ms latency, saves ~0.5-1.5W).";
      };

      pciRuntimePM = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set all PCI devices to auto power management on battery.";
      };

      usbAutosuspend = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable USB autosuspend on battery (excluding HID devices).";
      };

      dirtyWritebackCentisecs = lib.mkOption {
        type = lib.types.int;
        default = 6000;
        description = "vm.dirty_writeback_centisecs on battery (60s). Batches disk writes for power savings.";
      };

      noctaliaPerformanceMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable noctalia-shell performance mode on battery (disables shadows/animations).";
      };

      throttleFossilize = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Throttle Steam fossilize_replay shader pre-caching to 5% CPU on battery.";
      };

      stopLact = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Stop LACT GPU daemon on battery to prevent dGPU polling.";
      };

      bluetoothAutosuspend = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Bluetooth USB autosuspend on battery (may cause audio crackling). Disabled on AC.";
      };

      displayMode = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "2560x1600@60.000";
        description = "Display mode to set on battery (e.g. lower refresh rate). Requires displayOutput and displayUser.";
      };

      enableVrr = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable variable refresh rate on battery (panel can drop to lower Hz when idle).";
      };

      kbdBacklightOff = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "0012";
        description = "USB PID of QMK keyboard to turn off RGB backlight on battery (e.g. '0012' for Framework 16 ANSI). Restores previous brightness on AC.";
      };
    };

    onAC = {
      ppdProfile = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "power-saver" "balanced" "performance" ]);
        default = "balanced";
        description = "power-profiles-daemon profile to set when on AC.";
      };

      scxArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "--performance" ];
        description = "Arguments for scx_lavd scheduler on AC.";
      };

      dirtyWritebackCentisecs = lib.mkOption {
        type = lib.types.int;
        default = 500;
        description = "vm.dirty_writeback_centisecs on AC (5s, kernel default).";
      };

      displayMode = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "2560x1600@165.000";
        description = "Display mode to set on AC (e.g. restore high refresh rate). Requires displayOutput and displayUser.";
      };
    };

    displayOutput = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "eDP-2";
      description = "Wayland output name for display mode switching.";
    };

    displayUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Username to run niri display commands as.";
    };

    noctaliaUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Username to run noctalia IPC commands as. Required if noctaliaPerformanceMode is true.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Disable NMI watchdog — only needed for kernel debugging, saves ~1W
    boot.kernel.sysctl."kernel.nmi_watchdog" = 0;

    # Enable audio codec power management — codec sleeps after 1s of silence
    boot.extraModprobeConfig = "options snd_hda_intel power_save=1";

    # Power-switch scripts available on PATH
    environment.systemPackages = [
      powerSwitchBattery
      powerSwitchAC
    ] ++ lib.optional cfg.onBattery.throttleFossilize fossilizeUnthrottle;

    # Udev rule to detect AC/battery transitions
    services.udev.extraRules = ''
      # Power management: trigger systemd targets on AC/battery change
      ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", TAG+="systemd", ENV{SYSTEMD_WANTS}="power-on-battery.target"
      ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}="power-on-ac.target"
    '';

    systemd = {
      # Targets triggered by udev
      targets = {
        power-on-battery = {
          description = "Power source changed to battery";
        };
        power-on-ac = {
          description = "Power source changed to AC";
        };
      };

      # Fossilize throttle slice with CPU limit
      slices = lib.mkIf cfg.onBattery.throttleFossilize {
        fossilize-throttle = {
          description = "CPU-throttled slice for fossilize shader pre-caching";
          sliceConfig = {
            CPUQuota = "5%";
          };
        };
      };

      services = {
        # Battery mode switch service
        power-switch-battery = {
          description = "Apply battery power-saving settings";
          wantedBy = [ "power-on-battery.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${powerSwitchBattery}/bin/power-switch-battery";
          };
        };

        # AC mode switch service
        power-switch-ac = {
          description = "Apply AC performance settings";
          wantedBy = [ "power-on-ac.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${powerSwitchAC}/bin/power-switch-ac";
          };
        };

        # Boot-time detection of initial power state
        power-detect-initial = {
          description = "Detect initial power source and apply settings";
          wantedBy = [ "multi-user.target" ];
          after = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "power-detect-initial" ''
              # Wait briefly for power supply sysfs to stabilize
              sleep 2

              # Check AC power status
              ac_online=0
              for ac in /sys/class/power_supply/AC* /sys/class/power_supply/ACAD*; do
                if [ -f "$ac/online" ]; then
                  ac_online=$(cat "$ac/online" 2>/dev/null || echo 0)
                  break
                fi
              done

              if [ "$ac_online" = "1" ]; then
                echo "Boot: AC power detected, applying AC settings"
                ${powerSwitchAC}/bin/power-switch-ac
              else
                echo "Boot: Battery power detected, applying battery settings"
                ${powerSwitchBattery}/bin/power-switch-battery
              fi
            '';
          };
        };

        # Fossilize throttle service (moves fossilize processes into throttled cgroup)
        fossilize-throttle = lib.mkIf cfg.onBattery.throttleFossilize {
          description = "Throttle fossilize_replay shader pre-caching processes";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "fossilize-throttle" ''
              # Find all fossilize_replay processes and SIGSTOP them
              # New ones spawned by Steam will be caught on the next timer tick
              ${pkgs.procps}/bin/pkill -STOP -f fossilize_replay 2>/dev/null || true
            '';
          };
        };
      };

      # Fossilize throttle timer (only active on battery)
      timers = lib.mkIf cfg.onBattery.throttleFossilize {
        fossilize-throttle = {
          description = "Periodically throttle fossilize_replay processes";
          # Not enabled by default - started/stopped by power-switch scripts
          timerConfig = {
            OnActiveSec = "0";
            OnUnitActiveSec = "10s";
            AccuracySec = "5s";
          };
        };
      };
    };

    # Add EnvironmentFile drop-in to scx service so power-switch scripts
    # can override SCX_FLAGS_OVERRIDE at runtime via /run/power-management/scx.env
    systemd.services.scx.serviceConfig.EnvironmentFile = lib.mkIf (config.services.scx.enable) [
      "-/run/power-management/scx.env"
    ];
  };
}
