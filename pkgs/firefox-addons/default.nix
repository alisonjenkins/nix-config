{
  pkgs,
  lib,
  ...
}: {
  media-bridge = pkgs.stdenv.mkDerivation rec {
    pname = "media-bridge";
    version = "1.0.0";

    src = pkgs.fetchurl {
      url = "https://addons.mozilla.org/firefox/downloads/file/4633663/media_bridge-${version}.xpi";
      sha256 = "sha256-DYqEKPY34iAHIzkrVl0xdTJGWG7Jdj25BjoZp8U8D+Q=";
    };

    preferLocalBuild = true;
    allowSubstitutes = false;

    dontUnpack = true;
    dontBuild = true;
    dontPatchELF = true;
    dontStrip = true;

    installPhase = ''
      mkdir -p "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
      install -Dm644 "$src" "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/media-bridge@mediabridge.addon.xpi"
    '';

    passthru = {
      addonId = "media-bridge@mediabridge.addon";
    };

    meta = {
      description = "Creates per-tab MPRIS players using a native messaging bridge";
      homepage = "https://addons.mozilla.org/en-US/firefox/addon/media-bridge/";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };
}
