{
  config,
  pkgs,
  lib,
  hostname ? "ali-work-laptop",
  ...
}: let
  secretsFile = ../../../../secrets/${hostname}/locations.yaml;
  secretsFileExists = builtins.pathExists secretsFile;
in {
  home.packages = [pkgs.detect-location];

  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

  sops.secrets = lib.mkIf secretsFileExists {
    "locations-config" = {
      path = "${config.home.homeDirectory}/.config/location-detection/locations.yaml";
      sopsFile = secretsFile;
      format = "yaml";
      key = "";
    };
  };

  home.sessionVariables = lib.mkIf secretsFileExists {
    LOCATION_CONFIG = "${config.home.homeDirectory}/.config/location-detection/locations.yaml";
  };

  warnings = lib.mkIf (!secretsFileExists) [
    "Location detection: secrets/${hostname}/locations.yaml not found. Create it using the template in home/machines/locations.yaml.template"
  ];
}
