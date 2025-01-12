{ config, pkgs, ... }: {
  xdg.configFile."openxr/1/active_runtime.json".source = if pkgs.stdenv.isLinux then "${pkgs.wivrn}/share/openxr/1/openxr_wivrn.json" else "";

  xdg.configFile."openvr/openvrpaths.vrpath".text =
    if pkgs.stdenv.isLinux then ''
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
    '' else "";
}

