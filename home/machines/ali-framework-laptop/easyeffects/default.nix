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
  # ~/.config/easyeffects/ (the 7.x path) -- matches the fetched profiles
  # below, which already used the correct path.
  profileFileAttrs = lib.mapAttrs' (
    filename: _:
      lib.nameValuePair
      ".local/share/easyeffects/output/${filename}"
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
  # Keys are "<sink node.name>:<active route name>"; EasyEffects matches both.
  autoloadRules = {
    "alsa_output.pci-0000_c4_00.6.analog-stereo:Speakers" = {
      device = "alsa_output.pci-0000_c4_00.6.analog-stereo";
      device-description = "Ryzen HD Audio Controller Analog Stereo";
      device-profile = "Speakers";
      preset-name = "Gracefu's Edits";
    };
    "bluez_output.88_C9_E8_06_5E_9C.1:Headphones" = {
      device = "bluez_output.88_C9_E8_06_5E_9C.1";
      device-description = "WH-1000XM5";
      device-profile = "Headphones";
      preset-name = "WH-1000XM5";
    };
  };

  autoloadFileAttrs = lib.mapAttrs' (
    key: rule:
      lib.nameValuePair
      ".local/share/easyeffects/autoload/output/${key}.json"
      {text = builtins.toJSON rule;}
  ) autoloadRules;

  followDefaultSink = pkgs.writeShellApplication {
    name = "easyeffects-follow-default-sink";
    runtimeInputs = with pkgs; [pipewire wireplumber jq gawk gnused gnugrep coreutils];
    text = builtins.readFile ./follow-default-sink.sh;
  };
in {
  home.packages = [pkgs.easyeffects];

  systemd.user.services.easyeffects-follow-default-sink = {
    Unit = {
      Description = "Move EasyEffects output to the default sink when it misses a change";
      After = ["pipewire.service" "wireplumber.service"];
      PartOf = ["pipewire.service"];
    };
    Service = {
      ExecStart = lib.getExe followDefaultSink;
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["pipewire.service"];
  };

  home.file =
    profileFileAttrs
    // autoloadFileAttrs
    // {
      ".local/share/easyeffects/output/.keep".text = "";
      ".local/share/easyeffects/output/Gracefu's Edits.json" = {
        source = frameworkDspProfile;
      };
      ".local/share/easyeffects/irs/IR_22ms_27dB_5t_15s_0c.irs" = {
        source = frameworkDspImpulseResponse;
      };
    };
}
