{ stdenvNoCC, stdenv, lib, fetchurl, unzip, bash }:
let
  # v1.05 server pack base + 17 mod-jar overlays from v1.06 client
  # (publisher hasn't shipped a v1.06 server pack — see v106-overlays.nix).
  version = "1.06";

  serverPack = fetchurl {
    url = "https://mediafilez.forgecdn.net/files/7413/402/CSC%20Server%20Pack-v1.05.zip";
    name = "CSC-Server-Pack-v1.05.zip";
    sha256 = "11d6cj1qnii6cl0gvqp32y6hr20q07rgxlwbkzcf9m86y4yisqff";
  };

  perfMods = import ./perf-mods.nix { inherit fetchurl; };
  jvmArgs = import ./jvm-args.nix;
  v106Overlays = import ./v106-overlays.nix { inherit fetchurl; };

  eulaFile = builtins.toFile "eula.txt" "eula=true\n";
  jvmArgsFile = builtins.toFile "user_jvm_args.txt" jvmArgs;
in
stdenvNoCC.mkDerivation {
  pname = "create-sky-colonies-server";
  inherit version;

  src = serverPack;
  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    runHook preUnpack
    mkdir -p server
    unzip -q $src -d server
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r server/. $out/

    # FerriteCore 6.0.1 and Saturn 0.1.3 already ship in the pack — adding
    # them here would create duplicate-mod load errors. Only add the perf
    # mods that are NOT already present.
    install -m644 ${perfMods.canary}        $out/mods/canary-mc1.20.1-0.3.3.jar
    install -m644 ${perfMods.modernfix}     $out/mods/modernfix-forge-5.27.15+mc1.20.1.jar
    install -m644 ${perfMods.noisium}       $out/mods/noisium-forge-2.3.0+mc1.20-1.20.1.jar
    install -m644 ${perfMods.memoryleakfix} $out/mods/memoryleakfix-forge-1.17+-1.1.5.jar
    install -m644 ${perfMods.spark}         $out/mods/spark-1.10.53-forge.jar

    install -m644 ${eulaFile}        $out/eula.txt
    install -m644 ${jvmArgsFile}     $out/user_jvm_args.txt
    install -m755 ${./entrypoint.sh} $out/entrypoint.sh
    # Replace the portable shebang with an absolute store path
    # (dockerTools images contain only /nix/store, no /usr/bin/env)
    # and substitute the libstdc++ path for spark's async-profiler.
    substituteInPlace $out/entrypoint.sh \
        --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash' \
        --replace-fail '@libstdcxxLib@'      '${stdenv.cc.cc.lib}/lib'

    # Strip client-only rendering mods that detect
    # `FMLEnvironment.dist == CLIENT` and no-op server-side. Removing
    # them does not change game behavior (clients still ship them, mod
    # list handshake tolerates server-missing client-only mods).
    rm $out/mods/ImmediatelyFast-Forge-1.5.3+1.20.4.jar
    rm $out/mods/sodiumdynamiclights-forge-1.0.10-1.20.1.jar

    # v1.06 mod-jar overlays — publisher hasn't shipped a v1.06 server
    # pack yet, so we patch the v1.05 server tree in place with the
    # v1.06 versions of the 17 mods that bumped (sourced from the
    # v1.06 client pack manifest). Keeps client/server mod versions
    # in sync for clients running v1.06.
    ${lib.concatMapStrings (m: ''
      rm -f "$out/mods/${m.v105Filename}"
      install -m644 "${m.v106Jar}" "$out/mods/${m.v106Filename}"
    '') v106Overlays}

    # Admin-tunable defaults (4-player target).
    chmod +w $out/server.properties
    sed -i \
        -e 's/^max-players=.*/max-players=4/' \
        -e 's/^view-distance=.*/view-distance=4/' \
        -e 's/^simulation-distance=.*/simulation-distance=2/' \
        $out/server.properties
    chmod -w $out/server.properties

    runHook postInstall
  '';

  meta = with lib; {
    description = "Create Sky Colonies (VS X Create 6.0) modpack server, prepared for OCI container";
    homepage = "https://www.curseforge.com/minecraft/modpacks/create-sky-colonies-valkyrian-skies-x-create-6-0";
    license = licenses.unfreeRedistributable;
    platforms = platforms.linux;
  };
}
