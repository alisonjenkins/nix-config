{
  config,
  pkgs,
  lib,
  hostname ? "ali-work-laptop",
  ...
}: let
  secretsFile = ../../../secrets/${hostname}/locations.yaml;
  secretsFileExists = builtins.pathExists secretsFile;
in {
  home.packages = [pkgs.detect-location];

  sops.secrets = lib.mkIf secretsFileExists {
    "location-detection/locations" = {
      path = "${config.home.homeDirectory}/.config/location-detection/locations.yaml";
      sopsFile = secretsFile;
    };
  };

  home.sessionVariables = lib.mkIf secretsFileExists {
    LOCATION_CONFIG = "${config.home.homeDirectory}/.config/location-detection/locations.yaml";
  };
}
