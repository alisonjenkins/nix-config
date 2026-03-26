{ pkgs, ... }:

let
  addon = { pname, version, addonId, url, sha256 }:
    pkgs.stdenv.mkDerivation {
      name = "${pname}-${version}";
      src = pkgs.fetchurl { inherit url sha256; };
      preferLocalBuild = true;
      allowSubstitutes = true;
      buildCommand = ''
        dst="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${addonId}.xpi"
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
      '';
    };

  tbkeys = pkgs.stdenv.mkDerivation {
    name = "tbkeys-lite-custom";
    src = pkgs.fetchFromGitHub {
      owner = "wshanks";
      repo = "tbkeys";
      rev = "main";
      sha256 = "0spyzp5dgjs228q03i85w74956axqx4zq7g1zlxgw2vaj013w6zc";
    };
    nativeBuildInputs = [ pkgs.zip pkgs.jq ];
    installPhase = ''
      mkdir -p $out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}
      
      # Copy addon source
      cp -r addon src
      cd src
      
      # Transform to Lite (remove eval)
      sed -i 's#^.*eval(.*#// Do nothing#' implementation.js
      
      # Update Manifest ID to lite
      jq '.browser_specific_settings.gecko.id = "tbkeys-lite@addons.thunderbird.net"' manifest.json > manifest.json.tmp
      mv manifest.json.tmp manifest.json
      
      # Zip it
      zip -r $out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/tbkeys-lite@addons.thunderbird.net.xpi .
    '';
  };

  quickfolders = addon {
    pname = "quickfolders";
    version = "latest";
    addonId = "quickfolders@curious.be";
    url = "https://addons.thunderbird.net/thunderbird/downloads/latest/quickfolders-tabbed-folders/latest.xpi";
    sha256 = "0hh0mm4r4rg70mdg2ysly0i7kr0vz7ih061q93hl8j5k3486gyfl";
  };

  cardbook = addon {
    pname = "cardbook";
    version = "latest";
    addonId = "cardbook@vigneau.philippe";
    url = "https://addons.thunderbird.net/thunderbird/downloads/latest/cardbook/latest.xpi";
    sha256 = "1cm1r5ygr4si4spdki72jafsjv97pknhgvxm085lpvwa5an74apb";
  };
in
{
  programs.thunderbird = {
    enable = true;
    profiles.ali = {
      isDefault = true;
      settings = {
        "extensions.strictCompatibility" = false;
        "extensions.checkCompatibility.146.0" = false;
        "extensions.checkCompatibility.nightly" = false;
      };
      extensions = [ tbkeys quickfolders cardbook ];
    };
  };
}
