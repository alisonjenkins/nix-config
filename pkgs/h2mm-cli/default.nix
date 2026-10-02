# h2mm-cli (v4n00/h2mm-cli) — DEPRECATED upstream as of 2025-09-30 in favor
# of Arsenal (pkgs/arsenal), which gained Linux support in its 0.30.0
# release. Also has a confirmed, unfixed bug (upstream issue #96: mods show
# ENABLED in `h2mm list` but have zero effect in-game) and the repo has had
# no code commits since the deprecation. home/modules/helldivers2-mods no
# longer installs this — kept here only because it still builds and may be
# useful for one-off CLI scripting (e.g. `h2mm modpack switch`) against an
# existing mods.csv. See the helldivers2-modding skill for the full
# incident writeup. Do not use `h2mm install`/`enable` to deploy a mod;
# use pkgs/arsenal instead.
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
