# BellSoft Liberica JDK 21 with CRaC (Coordinated Restore at Checkpoint).
#
# Stock OpenJDK / Temurin can't checkpoint a running JVM. Liberica's CRaC
# build ships the CRaC JVM API plus a bundled `criu` + `criuengine` under
# lib/, so `jcmd <pid> JDK.checkpoint` works without a system-wide criu
# install. We use it to bake a warmed Minecraft server JVM (mods +
# registries + JIT) and restore it in milliseconds instead of the 5-8 min
# cold boot — see pkgs/create-arkana-aeronautics-server.
#
# x86_64 only for now (this is what we develop/checkpoint on). aarch64 is a
# one-line addition (swap arch + amd64->aarch64 in the url + its sha256)
# once the x86_64 snapshot pipeline works end-to-end.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
# JDK runtime libs (standard nixpkgs binary-JDK set)
, alsa-lib
, cups
, fontconfig
, freetype
, glibc
, libffi
, zlib
, libx11
, libxext
, libxi
, libxrender
, libxt
, libxtst
# bundled-criu runtime libs
, libnl
, protobufc
, libnet
, libcap
}:

let
  version = "21.0.11+12";
  # The tarball unpacks to this directory.
  rootDir = "jdk-21.0.11-crac";
in
stdenv.mkDerivation {
  pname = "liberica-jdk-crac";
  inherit version;

  src = fetchurl {
    url = "https://github.com/bell-sw/Liberica/releases/download/${version}/bellsoft-jdk${version}-linux-amd64-crac.tar.gz";
    sha256 = "12yr3p7xl4jyg43014mqzdqfqby1lshjhdqlrxffcm7cn43nipgd";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    stdenv.cc.cc.lib
    alsa-lib
    cups
    fontconfig
    freetype
    glibc
    libffi
    zlib
    libx11
    libxext
    libxi
    libxrender
    libxt
    libxtst
    # criu / criuengine
    libnl
    protobufc
    libnet
    libcap
  ];

  # The CRaC restore path (criu) re-exec's binaries by absolute store path
  # at runtime; don't let autoPatchelf shrink/strip in ways that break the
  # bundled criu helper.
  dontStrip = true;

  sourceRoot = rootDir;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a ./. $out/
    runHook postInstall
  '';

  passthru = {
    home = "${placeholder "out"}";
  };

  meta = with lib; {
    description = "BellSoft Liberica JDK 21 with CRaC (checkpoint/restore), bundled criu";
    homepage = "https://bell-sw.com/pages/downloads/#jdk-21-lts";
    license = licenses.gpl2Only; # GPLv2+CE, like OpenJDK
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
