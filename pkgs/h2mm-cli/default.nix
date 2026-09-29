# h2mm-cli (v4n00/h2mm-cli) — the only Linux-native Helldivers 2 mod manager
# today. The upstream author's own install.sh points users at the "Arsenal"
# GUI mod manager instead, but Arsenal's Linux support is still unreleased
# (planned v0.30 as of 2026-09) — h2mm-cli is what actually runs here.
#
# Upstream ships the tool as a single committed bash script (no build step,
# no releases artifact), so this package is just fetchurl + wrapProgram, not
# a real build. Pinned by content hash, not a git rev, since the repo has no
# tags — bump both `version` and `hash` together from
# https://raw.githubusercontent.com/v4n00/h2mm-cli/master/version and the
# adjacent `h2mm` script when upstream updates.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bash,
  coreutils,
  gnused,
  gawk,
  curl,
  unzip,
  zip,
  findutils,
}:
stdenvNoCC.mkDerivation {
  pname = "h2mm-cli";
  version = "0.7.0";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/v4n00/h2mm-cli/master/h2mm";
    hash = "sha256-OoA4QaGDchnIckcjSxP0Se5x5IWmzRswDVADaFU/skU=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/h2mm

    wrapProgram $out/bin/h2mm \
      --prefix PATH : ${lib.makeBinPath [
        bash
        coreutils
        gnused
        gawk
        curl
        unzip
        zip
        findutils
      ]}

    runHook postInstall
  '';

  meta = {
    description = "Linux-native CLI mod manager for Helldivers 2 (mod install/enable/order, no Windows/Nexus-app dependency)";
    homepage = "https://github.com/v4n00/h2mm-cli";
    license = lib.licenses.unfree; # upstream ships no LICENSE file
    platforms = lib.platforms.linux;
    mainProgram = "h2mm";
  };
}
