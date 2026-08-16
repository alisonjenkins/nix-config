{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.camera-resume;

  stateDir = "/run/camera-resume";

  # Shell-quoted "vid pid" pairs, fed to the record/recover loops below.
  deviceList = concatMapStringsSep "\n" (d: "${d.vendorId} ${d.productId}") cfg.devices;

  udevRules = concatMapStringsSep "\n" (d: ''
    SUBSYSTEM=="video4linux", ATTRS{idVendor}=="${d.vendorId}", ATTRS{idProduct}=="${d.productId}", ATTR{index}=="0", SYMLINK+="${d.symlink}"
  '') (filter (d: d.symlink != null) cfg.devices);

  # Root, because rebinding a USB port writes to /sys/bus/usb/drivers/usb.
  # Anything that has to talk to the user's PipeWire goes through this.
  asUser = "${pkgs.util-linux}/bin/runuser -u ${cfg.user} --";
in {
  options.services.camera-resume = {
    enable = mkEnableOption ''
      USB camera recovery across suspend/resume.

      An S3 suspend cuts VBUS to the root hubs ("root hub lost power or was
      reset"), so every USB device disconnects and re-enumerates on wake,
      usually landing on a different /dev/videoN. This module gives the
      camera a stable /dev symlink, rebinds its USB port if it fails to come
      back at all, and restarts the PipeWire-side consumers that were left
      pointing at the dead node.

      It cannot revive an already-running browser capture: a MediaStream
      whose device disappeared is ended permanently by the browser, and the
      page has to reacquire it. Only s2idle (modules.base.suspendState =
      "freeze") avoids that, at the cost of idle power
    '';

    user = mkOption {
      type = types.str;
      description = "User whose PipeWire session owns the cameras.";
    };

    devices = mkOption {
      description = "USB cameras to track across suspend.";
      default = [];
      example = literalExpression ''
        [
          {
            name = "OBSBOT Tiny 2 Lite";
            vendorId = "3564";
            productId = "fef9";
            symlink = "webcam";
          }
        ]
      '';
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Human-readable name, used only in log lines.";
          };
          vendorId = mkOption {
            type = types.strMatching "[0-9a-f]{4}";
            description = "USB idVendor, lowercase hex, as printed by lsusb.";
          };
          productId = mkOption {
            type = types.strMatching "[0-9a-f]{4}";
            description = "USB idProduct, lowercase hex, as printed by lsusb.";
          };
          symlink = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "webcam";
            description = ''
              Name under /dev for a stable symlink to the camera's capture
              node, for consumers that hardcode a path. Null to skip.

              Points at the interface's first video node (ATTR{index}=="0");
              UVC cameras expose a second one for metadata.
            '';
          };
        };
      });
    };

    settleSeconds = mkOption {
      type = types.ints.positive;
      default = 20;
      description = ''
        How long to wait for a camera to re-enumerate after resume before
        treating it as lost and rebinding its USB port. Re-enumeration took
        ~9s on ali-desktop, and the port rebind is disruptive, so leave
        generous headroom.
      '';
    };

    frameProbeSeconds = mkOption {
      type = types.ints.positive;
      default = 8;
      description = ''
        How long to wait for a single frame when checking that a camera is
        actually awake. A healthy OBSBOT delivers one in well under a second;
        a sleeping one delivers nothing at all, so this only has to outlast
        the open/STREAMON handshake.
      '';
    };

    restartVirtualCameras = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Restart any virtual-camera@N feeders that were running before the
        suspend. Their gstreamer pipeline dies with the camera node and does
        not re-establish itself.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.devices != [];
        message = "services.camera-resume.devices must list at least one camera.";
      }
    ];

    services.udev.extraRules = mkIf (udevRules != "") udevRules;

    # Records where each camera currently sits on the USB tree. On resume the
    # device may be gone entirely, and then there is nothing left to derive
    # the port from -- so it has to be captured while it is still attached.
    systemd.services.camera-pre-suspend = {
      description = "Record USB camera port paths before suspend";
      before = ["sleep.target"];
      wantedBy = ["sleep.target"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "camera-pre-suspend" ''
          set -u
          ${pkgs.coreutils}/bin/mkdir -p ${stateDir}
          ${pkgs.coreutils}/bin/rm -f ${stateDir}/*.port

          while read -r vid pid; do
            [ -n "$vid" ] || continue
            for d in /sys/bus/usb/devices/*; do
              [ -r "$d/idVendor" ] && [ -r "$d/idProduct" ] || continue
              [ "$(${pkgs.coreutils}/bin/cat "$d/idVendor")" = "$vid" ] || continue
              [ "$(${pkgs.coreutils}/bin/cat "$d/idProduct")" = "$pid" ] || continue
              ${pkgs.coreutils}/bin/basename "$d" > "${stateDir}/$vid:$pid.port"
              echo "camera-resume: $vid:$pid at USB port $(${pkgs.coreutils}/bin/cat "${stateDir}/$vid:$pid.port")"
            done
          done <<'EOF'
          ${deviceList}
          EOF
        '';
      };
    };

    systemd.services.camera-resume = {
      description = "Recover USB cameras after resume from suspend";
      after = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
        "suspend-then-hibernate.target"
        # Both hooks poke the same PipeWire instance; let the audio one finish
        # its card-profile cycling first rather than interleave with it.
        "audio-context-resume.service"
      ];
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "camera-resume" (''
          set -u

          uid=$(${pkgs.coreutils}/bin/id -u ${cfg.user})
          export XDG_RUNTIME_DIR="/run/user/$uid"
          export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"

          # First capture node (ID_V4L_CAPABILITIES=:capture:) belonging to the
          # given USB ids, or empty if the camera is not enumerated at all.
          capture_node() {
            local vid="$1" pid="$2" v props
            for v in /dev/video*; do
              [ -e "$v" ] || continue
              props=$(${pkgs.systemd}/bin/udevadm info -q property "$v" 2>/dev/null) || continue
              case "$props" in *"ID_VENDOR_ID=$vid"*) ;; *) continue ;; esac
              case "$props" in *"ID_MODEL_ID=$pid"*) ;; *) continue ;; esac
              case "$props" in *":capture:"*) ;; *) continue ;; esac
              echo "$v"
              return 0
            done
            return 1
          }

          wait_for_node() {
            local vid="$1" pid="$2" i=0 node
            while [ "$i" -lt ${toString cfg.settleSeconds} ]; do
              if node=$(capture_node "$vid" "$pid"); then
                echo "$node"
                return 0
              fi
              ${pkgs.coreutils}/bin/sleep 1
              i=$((i + 1))
            done
            return 1
          }

          # A camera can enumerate perfectly and still hand out nothing: the
          # OBSBOT Tiny 2 Lite comes back from S3 with its gimbal parked down
          # in sleep mode, offering formats and accepting opens while its
          # sensor stays off. So presence is not health -- pull a frame.
          #
          # Skipped when something already holds the device (EBUSY), since a
          # live consumer is itself proof that frames flow.
          has_frames() {
            local node="$1" out
            out=$(${pkgs.coreutils}/bin/timeout ${toString cfg.frameProbeSeconds} \
              ${pkgs.v4l-utils}/bin/v4l2-ctl -d "$node" --stream-mmap --stream-count=1 2>&1)
            case "$out" in
              *"resource busy"*) return 0 ;;
              *"<"*) return 0 ;;
              *) return 1 ;;
            esac
          }

          # Last resort when the device never came back: cycle the port it was
          # attached to before the suspend, which re-runs enumeration for it.
          # Note this does not drop VBUS, so it cannot wake a camera that slept
          # at the firmware level -- only a real replug does that.
          rebind_port() {
            local vid="$1" pid="$2" port
            [ -r "${stateDir}/$vid:$pid.port" ] || return 1
            port=$(${pkgs.coreutils}/bin/cat "${stateDir}/$vid:$pid.port")
            [ -e "/sys/bus/usb/devices/$port" ] || return 1
            echo "camera-resume: $vid:$pid missing, rebinding USB port $port"
            echo "$port" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null || return 1
            ${pkgs.coreutils}/bin/sleep 2
            echo "$port" > /sys/bus/usb/drivers/usb/bind 2>/dev/null || return 1
            return 0
          }

          recovered=0

          while read -r vid pid; do
            [ -n "$vid" ] || continue

            if ! node=$(wait_for_node "$vid" "$pid"); then
              rebind_port "$vid" "$pid" || {
                echo "camera-resume: $vid:$pid did not return and could not be rebound" >&2
                continue
              }
              node=$(wait_for_node "$vid" "$pid") || {
                echo "camera-resume: $vid:$pid still absent after rebind" >&2
                continue
              }
            fi

            echo "camera-resume: $vid:$pid present at $node"

            # Present but dead: try the rebind once, and if the sensor is still
            # dark say so out loud. Nothing short of cutting VBUS wakes it, and
            # this host's hub cannot, so the only remaining fix is a human
            # pulling the cable -- silently "succeeding" here would leave a
            # camera that looks fine everywhere and shows a black frame.
            if ! has_frames "$node"; then
              echo "camera-resume: $node enumerated but produced no frames, rebinding"
              if rebind_port "$vid" "$pid"; then
                node=$(wait_for_node "$vid" "$pid") || node=""
              fi
              if [ -z "$node" ] || ! has_frames "$node"; then
                echo "camera-resume: $vid:$pid is asleep -- needs a physical replug" >&2
                ${asUser} ${pkgs.libnotify}/bin/notify-send -u critical \
                  "Camera asleep" \
                  "The camera came back from suspend without a working sensor. Unplug and replug it." \
                  2>/dev/null || true
                continue
              fi
            fi

            recovered=$((recovered + 1))

            # The kernel device is back, but WirePlumber's V4L2 monitor can miss
            # the re-add and leave no node for it -- then every PipeWire client
            # sees no camera at all. Only restart when that actually happened;
            # a restart drops in-flight audio streams too.
            if ! ${asUser} ${pkgs.pipewire}/bin/pw-dump 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "\"$node\""; then
              echo "camera-resume: no PipeWire node for $node, restarting wireplumber"
              ${asUser} ${pkgs.systemd}/bin/systemctl --user restart wireplumber
              ${pkgs.coreutils}/bin/sleep 3
            fi
          done <<'EOF'
          ${deviceList}
          EOF
        ''
        + optionalString cfg.restartVirtualCameras ''

          # Feeders whose gstreamer pipeline died with the old camera node.
          # Only the ones systemd still considers active are touched, so this
          # never lights the camera LED for feeders that were deliberately off.
          if [ "$recovered" -gt 0 ]; then
            ${asUser} ${pkgs.systemd}/bin/systemctl --user list-units --state=active --plain --no-legend 'virtual-camera@*.service' \
              | ${pkgs.gawk}/bin/awk '{print $1}' \
              | while read -r unit; do
                  [ -n "$unit" ] || continue
                  echo "camera-resume: restarting $unit"
                  ${asUser} ${pkgs.systemd}/bin/systemctl --user restart "$unit"
                done
          fi
        '');
      };
    };
  };
}
