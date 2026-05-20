{
  config,
  pkgs,
  lib,
  ...
}: let
  profilesDir = ./profiles;

  profileFiles =
    if builtins.pathExists profilesDir
    then
      lib.filterAttrs
      (name: type: type == "regular" && lib.hasSuffix ".json" name)
      (builtins.readDir profilesDir)
    else {};

  profileFileAttrs = lib.mapAttrs' (
    filename: _:
      lib.nameValuePair
      ".config/easyeffects/output/${filename}"
      {source = profilesDir + "/${filename}";}
  ) profileFiles;
in {
  home.packages = [pkgs.easyeffects];

  home.file =
    profileFileAttrs
    // {
      ".config/easyeffects/output/.keep".text = "";

      # Force Zen browser mic input to use the processed easyeffects_source
      # instead of the raw Scarlett ALSA capture. Without this, WirePlumber's
      # default-policy auto-links Zen to the raw mic *in addition to*
      # easyeffects_source, so remote listeners hear raw voice + delayed
      # processed voice = echo. Local recording tools (Audacity) read the raw
      # capture directly and don't surface the issue.
      ".config/wireplumber/wireplumber.conf.d/90-zen-mic-route.conf".text = ''
        node.rules = [
          {
            matches = [
              {
                application.name = "Zen"
                media.class = "Stream/Input/Audio"
              }
            ]
            actions = {
              update-props = {
                target.object = "easyeffects_source"
              }
            }
          }
        ]
      '';
    };
}
