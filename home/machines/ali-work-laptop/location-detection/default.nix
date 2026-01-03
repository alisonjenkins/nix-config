{
  config,
  pkgs,
  lib,
  hostname ? "ali-work-laptop",
  ...
}: let
  secretsFile = ../../../../secrets/${hostname}/locations.yaml;
in {
  home.packages = [pkgs.detect-location];

  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

  sops.secrets."locations-config" = {
    path = "${config.home.homeDirectory}/.config/location-detection/locations.yaml";
    sopsFile = secretsFile;
    format = "yaml";
    key = "";
  };

  home.sessionVariables.LOCATION_CONFIG = "${config.home.homeDirectory}/.config/location-detection/locations.yaml";
}
