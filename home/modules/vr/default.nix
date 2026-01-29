{ config, pkgs, enableOpenSourceVR ? false, ... }: {
  xdg.configFile = pkgs.lib.mkMerge [
    (pkgs.lib.mkIf (pkgs.stdenv.isLinux && enableOpenSourceVR) {
      "openxr/1/active_runtime.json".source = "${pkgs.wivrn}/share/openxr/1/openxr_wivrn.json";
      "openvr/openvrpaths.vrpath".text = ''
        {
          "config" :
          [
            "${config.xdg.dataHome}/Steam/config"
          ],
          "external_drivers" : null,
          "jsonid" : "vrpathreg",
          "log" :
          [
            "${config.xdg.dataHome}/Steam/logs"
          ],
          "runtime" :
          [
            "${pkgs.opencomposite}/lib/opencomposite"
          ],
          "version" : 1
        }
      '';
    })
    (pkgs.lib.mkIf (pkgs.stdenv.isLinux && !enableOpenSourceVR) {
      "openxr/1/active_runtime.json".source = ./steamxr_linux64.json;
      "openvr/openvrpaths.vrpath".source = ./openvrpaths.vrpath;
    })
  ];
}
