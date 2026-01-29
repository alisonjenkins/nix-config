{ pkgs, ... }:

let
  addon = { pname, version, addonId, url, sha256 }:
    pkgs.stdenv.mkDerivation {
      name = "${pname}-${version}";
      src = pkgs.fetchurl { inherit url sha256; };
      preferLocalBuild = true;
      allowSubstitutes = true;
      buildCommand = ''
        dst="$out/share/mozilla/extensions/{3550f703-e582-4d05-9a08-453d09bdfdc6}/${addonId}.xpi"
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
      '';
    };

  tbsync = addon {
    pname = "tbsync";
    version = "latest";
    addonId = "tbsync@jobisoft.de";
    url = "https://addons.thunderbird.net/thunderbird/downloads/latest/tbsync/latest.xpi";
    sha256 = "1fxwbf1azlby5p59vm7z2apqv7vsnmybd3gvxpf4jnhffw9a7av0";
  };

  eas = addon {
    pname = "eas-4-tbsync";
    version = "latest";
    addonId = "eas-4-tbsync@jobisoft.de"; 
    url = "https://addons.thunderbird.net/thunderbird/downloads/latest/eas-4-tbsync/latest.xpi";
    sha256 = "0rh4lx3xfbq2fg60hlm1g5hr9yrj6kx5vzx03k407xjb7q3c8r7m";
  };

  tbkeys = addon {
    pname = "tbkeys-lite";
    version = "latest";
    addonId = "tbkeys-lite@addons.thunderbird.net";
    url = "https://addons.thunderbird.net/thunderbird/downloads/latest/tbkeys-lite/latest.xpi";
    sha256 = "1v6p3smhhvks8ml6d7jihvpj1ngqkw2khsa2g7vhx74sxbn0ggc3";
  };
in
{
  programs.thunderbird = {
    enable = true;
    profiles.ali = {
      isDefault = true;
      extensions = [ tbsync eas tbkeys ];
    };
  };
}
