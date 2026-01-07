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

  # Framework DSP profile from https://github.com/cab404/framework-dsp
  frameworkDspProfile = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/cab404/framework-dsp/refs/heads/master/config/output/Gracefu's%20Edits.json";
    sha256 = "sha256-KZ8L1oEaeffLq9JkQ4lajwKXE34w8PdmmCs+NX44xkY=";
    name = "gracefus-edits.json";
  };

  frameworkDspImpulseResponse = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/cab404/framework-dsp/refs/heads/master/config/irs/IR_22ms_27dB_5t_15s_0c.irs";
    sha256 = "sha256-IxDXNhnTg/NrhPxA5+6u/meEnlX720eoQPyoJfbuge0=";
  };
in {
  home.packages = [pkgs.easyeffects];

  home.file =
    profileFileAttrs
    // {
      ".config/easyeffects/output/.keep".text = "";
      ".local/share/easyeffects/output/Gracefu's Edits.json" = {
        text = builtins.readFile frameworkDspProfile;
      };
      ".local/share/easyeffects/irs/IR_22ms_27dB_5t_15s_0c.irs" = {
        source = frameworkDspImpulseResponse;
      };
    };
}
