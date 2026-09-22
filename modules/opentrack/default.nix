{ config
, lib
, pkgs
, ...
}:
with lib; let
  cfg = config.modules.opentrack;

  # opentrack's Linux camera tracker opens a V4L2 device directly (OpenCV,
  # no PipeWire awareness), which would take exclusive access to whatever
  # /dev/videoN it's pointed at. Point it at a modules.virtual-cameras
  # loopback instead -- PipeWire keeps the real camera shared, and this
  # feeder is just one more consumer of it, same as a voice/video chat app.
  opentrackLaunch = pkgs.writeShellApplication {
    name = "opentrack-launch";
    runtimeInputs = [ pkgs.systemd pkgs.opentrack ];
    text = ''
      feeder="virtual-camera@${toString cfg.virtualCameraIndex}.service"
      systemctl --user start "$feeder"
      trap 'systemctl --user stop "$feeder" || true' EXIT
      opentrack
    '';
  };
in
{
  options.modules.opentrack = {
    enable = mkEnableOption ''
      opentrack head tracking, reading the webcam through a
      modules.virtual-cameras loopback slot instead of the real V4L2 device
      so it doesn't lock out other camera consumers (e.g. voice/video chat)
    '';

    virtualCameraIndex = mkOption {
      type = types.ints.positive;
      default = 1;
      description = ''
        Which modules.virtual-cameras loopback slot (1..count) opentrack
        reads from. Select the matching "Virtual Camera N" as opentrack's
        camera, or just run opentrack-launch, which starts that feeder
        first and stops it on exit.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.modules.virtual-cameras.enable or false;
        message = "modules.opentrack requires modules.virtual-cameras.enable = true -- opentrack reads a loopback slot, never the real camera device.";
      }
      {
        assertion = cfg.virtualCameraIndex <= (config.modules.virtual-cameras.count or 0);
        message = "modules.opentrack.virtualCameraIndex (${toString cfg.virtualCameraIndex}) exceeds modules.virtual-cameras.count (${toString (config.modules.virtual-cameras.count or 0)}).";
      }
    ];

    environment.systemPackages = [ pkgs.opentrack opentrackLaunch ];
  };
}
