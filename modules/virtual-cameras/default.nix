{ config
, lib
, pkgs
, ...
}:
with lib; let
  cfg = config.modules.virtual-cameras;

  indices = range 1 cfg.count;
  deviceNr = i: cfg.firstVideoNr + i - 1;

  # video_nr, card_label and exclusive_caps are per-device arrays; a single
  # value only applies to device 0, so those have to be spelled out in full.
  # max_buffers is NOT an array -- `modinfo -p v4l2loopback` reports it as a
  # plain (int), and passing a comma list makes the insert fail outright with
  # "`2,2,2,2' invalid for parameter `max_buffers'", so no loopbacks appear.
  commaList = f: concatStringsSep "," (map f indices);
  videoNrs = commaList (i: toString (deviceNr i));
  cardLabels = commaList (i: ''"${cfg.labelPrefix}${toString i}"'');
  exclusiveCaps = commaList (_: if cfg.exclusiveCaps then "1" else "0");
  maxBuffers = toString cfg.maxBuffers;

  gstPlugins = [
    # .out, not the default output: gstreamer's outputs are ordered
    # [ bin out dev debug ], so the bare attribute is the `bin` output, which
    # carries no lib/gstreamer-1.0 at all. Without it libgstcoreelements.so is
    # off the plugin path, decodebin cannot find `typefind`, and the pipeline
    # dies with "could not link pipewiresrc0 to decodebin0".
    pkgs.gst_all_1.gstreamer.out
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good # jpegdec for the camera's MJPG stream
    pkgs.pipewire # libgstpipewire.so -> pipewiresrc
  ];

  gstLaunch = "${pkgs.gst_all_1.gstreamer}/bin/gst-launch-1.0";

  targetProp = optionalString (cfg.target != null)
    '' target-object="${cfg.target}"'';

  # WirePlumber routes a stream by its media.class, and pipewiresrc does not
  # set one -- so the server has no candidate target and refuses the connect
  # with "stream error: target not found", target-object set or not. Declaring
  # the class is what makes a camera capture resolve at all.
  streamProps = ''stream-properties="props,media.class=Stream/Input/Video"'';

  # One feeder per loopback: PipeWire owns the physical camera, this pulls a
  # stream off it and writes raw frames into /dev/video<N>. PipeWire fans the
  # camera node out to as many consumers as ask for it, so several feeders
  # plus a native PipeWire client all share the one physical device.
  feeder = pkgs.writeShellScript "virtual-camera-feed" ''
    set -eu
    idx="$1"
    nr=$(( ${toString cfg.firstVideoNr} + idx - 1 ))
    dev="/dev/video$nr"

    if [ ! -e "$dev" ]; then
      echo "virtual-camera: $dev does not exist (is v4l2loopback loaded?)" >&2
      exit 1
    fi

    exec ${gstLaunch} -q \
      pipewiresrc${targetProp} ${streamProps} do-timestamp=true \
      ! decodebin \
      ! videoconvertscale \
      ! videorate \
      ! video/x-raw,format=${cfg.format},width=${toString cfg.width},height=${toString cfg.height},framerate=${toString cfg.framerate}/1 \
      ! v4l2sink device="$dev" sync=false
  '';

  vcam = pkgs.writeShellApplication {
    name = "vcam";
    runtimeInputs = [ pkgs.systemd pkgs.v4l-utils pkgs.coreutils ];
    text = ''
      COUNT=${toString cfg.count}
      FIRST=${toString cfg.firstVideoNr}

      usage() {
        cat <<EOF
      vcam - control the virtual cameras fed from the PipeWire camera node

        vcam start [N...|all]   start feeder(s)   (default: all)
        vcam stop  [N...|all]   stop feeder(s)    (default: all)
        vcam restart [N...|all]
        vcam status             show feeder state and device numbers
        vcam list               list all v4l2 devices

      N is 1..$COUNT, mapping to /dev/video\$((FIRST + N - 1)).
      EOF
      }

      expand() {
        if [ "$#" -eq 0 ] || [ "$1" = "all" ]; then
          seq 1 "$COUNT"
        else
          printf '%s\n' "$@"
        fi
      }

      act() {
        local verb="$1"; shift
        local n
        while read -r n; do
          systemctl --user "$verb" "virtual-camera@$n.service"
          echo "$verb virtual-camera@$n -> /dev/video$((FIRST + n - 1))"
        done < <(expand "$@")
      }

      cmd="''${1-status}"
      [ "$#" -gt 0 ] && shift || true

      case "$cmd" in
        start|stop|restart) act "$cmd" "$@" ;;
        status)
          for n in $(seq 1 "$COUNT"); do
            state=$(systemctl --user is-active "virtual-camera@$n.service" || true)
            printf '%-4s %-22s %s\n' "$n" "/dev/video$((FIRST + n - 1))" "$state"
          done
          ;;
        list) v4l2-ctl --list-devices ;;
        -h|--help|help) usage ;;
        *) usage; exit 1 ;;
      esac
    '';
  };
in
{
  options.modules.virtual-cameras = {
    enable = mkEnableOption ''
      virtual cameras (v4l2loopback) fed from the physical camera via PipeWire.
      PipeWire keeps exclusive ownership of the real device; native PipeWire
      clients use it directly, everything else uses a loopback
    '';

    count = mkOption {
      type = types.ints.positive;
      default = 4;
      description = "Number of v4l2loopback devices to create.";
    };

    firstVideoNr = mkOption {
      type = types.ints.unsigned;
      default = 10;
      description = ''
        /dev/videoN number of the first loopback. Kept well above the real
        capture devices so hardware numbering never collides.
      '';
    };

    labelPrefix = mkOption {
      type = types.str;
      default = "Virtual Camera ";
      description = "Card label prefix; the device index is appended.";
    };

    width = mkOption {
      type = types.ints.positive;
      default = 1280;
    };

    height = mkOption {
      type = types.ints.positive;
      default = 720;
    };

    framerate = mkOption {
      type = types.ints.positive;
      default = 30;
    };

    format = mkOption {
      type = types.str;
      default = "YUY2";
      description = ''
        Raw pixel format written into the loopback. YUY2 is understood by
        essentially every V4L2 consumer; NV12 halves the bandwidth but is not
        universally accepted.
      '';
    };

    target = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "alsa_input.usb-046d_HD_Pro_Webcam_C920";
      description = ''
        PipeWire node name or serial to capture from (pipewiresrc
        target-object). Null uses the default camera source.
      '';
    };

    exclusiveCaps = mkOption {
      type = types.bool;
      default = true;
      description = ''
        With exclusive_caps=1 a loopback only advertises capture capability
        while a feeder is writing to it, so apps never see a dead camera --
        but they must be started after `vcam start`. Set false to have the
        devices always enumerate (apps then show a black frame when idle).
      '';
    };

    maxBuffers = mkOption {
      type = types.ints.positive;
      default = 2;
      description = ''
        v4l2loopback ring buffers; low = low latency. Applies to every
        loopback -- the module parameter is a scalar, not a per-device array.
      '';
    };

    hideFromPipewire = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Stop WirePlumber's V4L2 monitor from picking the loopbacks back up as
        PipeWire camera sources, which would clutter the picker and invites
        feeding a loopback from itself.
      '';
    };
  };

  config = mkIf cfg.enable {
    boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    boot.kernelModules = [ "v4l2loopback" ];

    boot.extraModprobeConfig = ''
      options v4l2loopback devices=${toString cfg.count} video_nr=${videoNrs} card_label=${cardLabels} exclusive_caps=${exclusiveCaps} max_buffers=${maxBuffers}
    '';

    environment.systemPackages = [ vcam pkgs.v4l-utils ];

    services.pipewire.wireplumber.configPackages = mkIf cfg.hideFromPipewire [
      (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/55-hide-v4l2loopback.conf" ''
        monitor.v4l2.rules = [
          {
            matches = [
              {
                api.v4l2.cap.driver = "v4l2 loopback"
              }
            ]
            actions = {
              update-props = {
                device.disabled = true
                node.disabled = true
              }
            }
          }
        ]
      '')
    ];

    systemd.user.services."virtual-camera@" = {
      description = "Feed PipeWire camera into virtual camera %i";
      after = [ "pipewire.service" "wireplumber.service" ];
      wants = [ "pipewire.service" "wireplumber.service" ];
      # Deliberately not wantedBy anything: feeders are started on demand with
      # `vcam start`, so the camera LED stays off while nothing needs it.
      environment = {
        GST_PLUGIN_SYSTEM_PATH_1_0 = makeSearchPath "lib/gstreamer-1.0" gstPlugins;
      };
      serviceConfig = {
        Type = "exec";
        ExecStart = "${feeder} %i";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
