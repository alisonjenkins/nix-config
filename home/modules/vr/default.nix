{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;
in
{
  options.modules.vr = {
    enableOpenSourceVR = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Register WiVRn as the OpenXR runtime and OpenComposite as the OpenVR runtime for this user.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (pkgs.stdenv.isLinux && cfg.enableOpenSourceVR) {
      xdg.configFile."openxr/1/active_runtime.json".source =
        "${pkgs.wivrn}/share/openxr/1/openxr_wivrn.json";
      # openvrpaths.vrpath is owned by wivrn-server: it overwrites the file
      # at every startup from OVR_COMPAT_SEARCH_PATH (built into wivrn).
      # Managing it via home-manager produces a stale symlink that wivrn
      # silently replaces. The wivrn overlay pins the compat path to
      # OpenComposite only — wivrn-server will populate the file correctly.
    })
    (lib.mkIf (pkgs.stdenv.isLinux && !cfg.enableOpenSourceVR) {
      xdg.configFile."openxr/1/active_runtime.json".source = ./steamxr_linux64.json;
      xdg.configFile."openvr/openvrpaths.vrpath".source = ./openvrpaths.vrpath;
    })
  ];
}
