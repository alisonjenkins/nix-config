{ config, pkgs, enableOpenSourceVR ? false, ... }: {
  xdg.configFile = { } // (
    if pkgs.stdenv.isLinux && enableOpenSourceVR then
      {
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
      } else
      (if pkgs.stdenv.isLinux then {
        "openxr/1/active_runtime.json".source = ./steamxr_linux64.json;
        "openvr/openvrpaths.vrpath".source = ./openvrpaths.vrpath;
      } else { })
  );
}
