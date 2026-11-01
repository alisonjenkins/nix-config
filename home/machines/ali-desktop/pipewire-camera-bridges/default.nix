{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  cameraNode = "v4l2_input.pci-0000_15_00.0-usb-0_1.1_1.0";
  nodeName = config.custom.obsbotRawCamera.nodeName;
  nodeName720p = "obsbot-raw";
  virtualCameraNode = "obs-virtual-camera";
  # The first v4l2loopback device, numbered by modules.virtual-cameras.
  loopbackDevice = "/dev/video${toString osConfig.modules.virtual-cameras.firstVideoNr}";

  # gstreamer's core elements (capsfilter, queue) live in `out`, not the default `bin`.
  pluginPath = lib.makeSearchPath "lib/gstreamer-1.0" [
    pkgs.gst_all_1.gstreamer.out
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
    pkgs.pipewire
  ];

  bridge = name: text:
    pkgs.writeShellApplication {
      inherit name text;
      runtimeInputs = [pkgs.gst_all_1.gstreamer];
    };

  bridgeUnit = {
    description,
    exe,
    restartSec,
  }: {
    Unit = {
      Description = description;
      After = ["pipewire.service" "wireplumber.service"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      Type = "simple";
      ExecStart = lib.getExe exe;
      Environment = ["GST_PLUGIN_SYSTEM_PATH_1_0=${pluginPath}"];
      Restart = "always";
      RestartSec = restartSec;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  # Making the sink its own graph driver stops playback judder (without it frames arrive in bursts).
  driverProps = "node.driver=true,node.always-process=true,node.rate=1/60,node.latency=1/60";

  # A node has one fixed format and a consumer whose format doesn't intersect it fails the
  # link, so browsers (which ask for 720p) and OBS get separate nodes off the same camera mode.
  obsbotRaw = {
    name,
    node,
    description,
    size ? null,
  }: let
    scale = lib.optionalString (size != null) "videoscale ! ";
    dimensions = lib.optionalString (size != null) ",width=${toString size.width},height=${toString size.height}";
  in
    bridge name ''
      exec gst-launch-1.0 pipewiresrc target-object=${cameraNode} ! image/jpeg,width=1920,height=1080,framerate=60/1 ! jpegdec ! ${scale}videoconvert ! video/x-raw,format=YUY2${dimensions} ! pipewiresink mode=provide stream-properties="props,media.class=Video/Source,media.role=Camera,${driverProps},node.name=${node},node.description=${description}"
    '';

  # OBS writes 1080p60 (~250 MB/s) and the call consumer needs far less, so drop frames and
  # shrink before converting. The leaky queue keeps v4l2src draining when the consumer stalls,
  # and the sink follows the consumer's clock: as its own driver it stopped cycling and froze.
  obsVirtual = bridge "obs-virtual-camera" ''
    exec gst-launch-1.0 v4l2src device=${loopbackDevice} ! videorate drop-only=true ! video/x-raw,framerate=30/1 ! videoscale ! videoconvert ! video/x-raw,format=YUY2,width=1280,height=720 ! queue leaky=downstream max-size-buffers=2 ! pipewiresink mode=provide stream-properties="props,media.class=Video/Source,media.role=Camera,node.name=${virtualCameraNode},node.description=OBS-Virtual-Camera"
  '';
in {
  options.custom.obsbotRawCamera.nodeName = lib.mkOption {
    type = lib.types.str;
    default = "obsbot-raw-1080p";
    readOnly = true;
    description = "PipeWire node.name of the raw 1080p60 copy of the OBSBOT Tiny 2 Lite.";
  };

  config.systemd.user.services = {
    obsbot-raw-camera = bridgeUnit {
      description = "Publish the OBSBOT Tiny 2 Lite as a raw 1080p60 PipeWire video source";
      exe = obsbotRaw {
        name = "obsbot-raw-camera";
        node = nodeName;
        description = "OBSBOT-raw-1080p";
      };
      restartSec = 5;
    };

    obsbot-raw-camera-720p = bridgeUnit {
      description = "Publish the OBSBOT Tiny 2 Lite as a raw 720p60 PipeWire video source";
      exe = obsbotRaw {
        name = "obsbot-raw-camera-720p";
        node = nodeName720p;
        description = "OBSBOT-raw";
        size = {
          width = 1280;
          height = 720;
        };
      };
      restartSec = 5;
    };

    # v4l2src fails until OBS starts its virtual camera, so retry quietly.
    obs-virtual-camera = bridgeUnit {
      description = "Publish OBS's virtual camera as a PipeWire video source";
      exe = obsVirtual;
      restartSec = 10;
    };
  };
}
