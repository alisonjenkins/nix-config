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
      sha256 = "1ph3d8x0v3rmmj1b5s63b70civ2pcad3widvbinsf8glayqy6b3c";
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
    sha256 = "0c1b41mrhlkfhh1zqdvv7ifnd6m6zgsnsff4pg130r8yqbqxp434";
  };

  cardbook = addon {
    pname = "cardbook";
    version = "latest";
    addonId = "cardbook@vigneau.philippe";
    url = "https://addons.thunderbird.net/thunderbird/downloads/latest/cardbook/latest.xpi";
    sha256 = "1kbskn70496y26dgiw4ip8wv28zwk8m1hfjxa055d1zvag0y2xck";
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
