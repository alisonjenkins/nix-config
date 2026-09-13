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

  # EasyEffects 8.x reads presets from ~/.local/share/easyeffects/, not
  # ~/.config/easyeffects/ (the 7.x path).
  profileFileAttrs = lib.mapAttrs' (
    filename: _:
      lib.nameValuePair
      ".local/share/easyeffects/output/${filename}"
      {source = profilesDir + "/${filename}";}
  ) profileFiles;
in {
  home.packages = [pkgs.easyeffects];

  home.file =
    profileFileAttrs
    // {
      ".local/share/easyeffects/output/.keep".text = "";
    };
}
