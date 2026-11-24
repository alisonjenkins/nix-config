{ stdenvNoCC, stdenv, lib, fetchurl, bash, python3, openjdk21_headless, minecraft-modpack-tools
, # Groups (see groups.nix) baked into the server tree. Narrow it to bisect:
  #   .override { enabledGroups = [ "core-libs" "magic" ]; }
  enabledGroups ? lib.attrNames
    (lib.filterAttrs (_: g: g.enabledByDefault) (import ./groups.nix))
, # Server JDK. CVE-2026-114938 ("Java2Shell") is fixed from 21.0.13.1.
  jre ? openjdk21_headless
}:
let
  version = "0.2.1";
  minecraftVersion = "1.21.1";
  neoforgeVersion = "21.1.267";
  minJavaVersion = "21.0.13.1";

  neoforgeInstaller = fetchurl {
    url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/${neoforgeVersion}/neoforge-${neoforgeVersion}-installer.jar";
    name = "neoforge-${neoforgeVersion}-installer.jar";
    sha256 = "0q3yr5g2lf8xyg4z719q6gqrz3ka3v3dlfyjvz6bwni0h9pfdfr5";
  };

  # Vanilla item and advancement IDs for the quest check; the server jar
  # only appears once the NeoForge installer runs at first boot.
  vanillaClientJar = fetchurl {
    url = "https://piston-data.mojang.com/v1/objects/30c73b1c5da787909b2f73340419fdf13b9def88/client.jar";
    name = "minecraft-${minecraftVersion}-client.jar";
    sha256 = "168ckc453daiy1fgwcyrvjd1rq86h4nhf51i1xl1cxc3s6bni7s9";
  };

  generated = import ./mods.nix { inherit fetchurl; };
  groups = import ./groups.nix;
  extras = import ./extras.nix;

  unknownGroups = lib.filter (g: !(groups ? ${g})) enabledGroups;
  disabledSlugs = map (d: d.slug) extras.disabled;

  allEntries = generated.mods ++ generated.libs;
  enabledEntries = lib.filter
    (m: lib.elem m.group enabledGroups && !(lib.elem m.slug disabledSlugs))
    allEntries;
  serverMods = lib.filter (m: m.kind == "mod" && m.side != "client") enabledEntries;

  # Velocity-modern forwarding so the backend trusts mc-limbo-proxy. The fork
  # drops CrossStitch, which breaks command decoding through a transparent
  # proxy. Server only, and not on Modrinth/CurseForge, so it lives here rather
  # than in modlist.toml. Same jar as create-arkana-aeronautics-server.
  neoVelocity = fetchurl {
    url = "https://github.com/alisonjenkins/NeoVelocity/releases/download/fork-v1.2.6-nocrossstitch.1/neovelocity-1.2.6%2B1.21.1-1.21.5.jar";
    name = "neovelocity-1.2.6-nocrossstitch.jar";
    sha256 = "1vk2rli76v5bcxp7y7kdqay2xjfls1m81iynyn69ac5nzgl9sy4a";
  };

  eulaFile = builtins.toFile "eula.txt" "eula=true\n";
  jvmArgsFile = builtins.toFile "user_jvm_args.txt" (import ./jvm-args.nix);

  # Admins edit the volume copy; this is only the first-boot seed.
  serverProperties = builtins.toFile "server.properties" ''
    server-port=25565
    max-players=20
    view-distance=10
    simulation-distance=6
    motd=magic-vr-pack ${version}
    # Behind mc-limbo-proxy, which does the Mojang auth and forwards the
    # verified identity. Never expose this port directly.
    online-mode=false
    # RCON serves backup hooks; entrypoint.sh writes the password from
    # $RCON_PASSWORD and refuses to start without one. Restrict port 25575
    # with a NetworkPolicy.
    enable-rcon=true
    rcon.port=25575
    spawn-protection=0
    allow-flight=true
    sync-chunk-writes=false
  '';
in
assert lib.assertMsg (unknownGroups == [ ])
  "magic-vr-pack-server: unknown groups ${toString unknownGroups} (see groups.nix)";
assert lib.assertMsg (lib.versionAtLeast jre.version minJavaVersion)
  "magic-vr-pack-server: JDK ${jre.version} is older than ${minJavaVersion} (CVE-2026-114938)";
stdenvNoCC.mkDerivation {
  pname = "magic-vr-pack-server";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  nativeBuildInputs = [ minecraft-modpack-tools python3 ];

  installPhase = ''
    runHook preInstall

    # The eval-time assert reads the package's version attribute; this
    # asks the JVM itself, so a mislabelled or overridden JDK still fails.
    javaVersion="$(${jre}/bin/java -XshowSettings:properties -version 2>&1 \
      | sed -n 's/^ *java\.version = //p')"
    echo "[jdk-check] java.version=$javaVersion (need >= ${minJavaVersion})"
    lowest="$(printf '%s\n%s\n' "$javaVersion" "${minJavaVersion}" | sort -V | head -n1)"
    if [ -z "$javaVersion" ] || [ "$lowest" != "${minJavaVersion}" ]; then
      echo "[jdk-check] FAIL: JDK '$javaVersion' < ${minJavaVersion} (CVE-2026-114938)" >&2
      exit 1
    fi
    if ! ${jre}/bin/java $(grep -v '^ *#' ${jvmArgsFile}) -version >/dev/null 2>&1; then
      echo "[jvm-args] FAIL: JDK rejects a flag in user_jvm_args.txt" >&2
      ${jre}/bin/java $(grep -v '^ *#' ${jvmArgsFile}) -version >&2 || true
      exit 1
    fi

    mkdir -p $out/mods

    # Symlinked, not copied: each fetchurl path stays its own closure entry
    # so buildLayeredImage gives a mod bump its own OCI layer.
    ${lib.concatMapStrings (m: ''
      ln -s "${m.jar}" "$out/mods/${m.filename}"
    '') serverMods}
    ln -s "${neoVelocity}" "$out/mods/neovelocity-1.2.6-nocrossstitch.jar"

    install -m644 ${eulaFile}          $out/eula.txt
    install -m644 ${jvmArgsFile}       $out/user_jvm_args.txt
    install -m644 ${serverProperties}  $out/server.properties
    install -m644 ${neoforgeInstaller} $out/neoforge-installer.jar
    install -Dm644 ${./fml.toml}       $out/config/fml.toml
    install -Dm644 ${./DistantHorizons.toml} $out/config/DistantHorizons.toml
    install -Dm644 ${./neovelocity-common.toml} $out/config/neovelocity-common.toml
    # Per-section difficulty off: kills no longer raise an area's level.
    install -Dm644 ${./l2hostility-server.toml} $out/config/l2configs/l2hostility-server.toml

    python3 ${./quests}/gen.py $out
    # Server-side jars only: a quest item the server lacks never loads.
    registry-ids extract $out/mods ${vanillaClientJar} > registry-ids.json
    registry-ids check --ids registry-ids.json $out/config/ftbquests/quests

    install -m755 ${./entrypoint.sh} $out/entrypoint.sh
    install -m644 ${./rcon.sh}       $out/rcon.sh
    substituteInPlace $out/entrypoint.sh \
      --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash' \
      --replace-fail '@libstdcxxLib@'      '${stdenv.cc.cc.lib}/lib' \
      --replace-fail '@neoforgeVersion@'   '${neoforgeVersion}'

    echo "[deps-check] running dep-tree on $out ..."
    if dep-tree --neoforge-version ${neoforgeVersion} "$out" > deps-check.log 2>&1; then
      cat deps-check.log
      if grep -qE '^=== Missing required deps \([1-9]' deps-check.log; then
        echo "[deps-check] FAIL: missing required deps (see above)" >&2
        exit 1
      fi
      if grep -qE '^=== Required deps out of version range \([1-9]' deps-check.log; then
        echo "[deps-check] FAIL: version range mismatches (see above)" >&2
        exit 1
      fi
    else
      cat deps-check.log >&2
      echo "[deps-check] FAIL: analyzer crashed" >&2
      exit 1
    fi

    runHook postInstall
  '';

  passthru = {
    inherit neoforgeVersion minecraftVersion jre enabledGroups;
    mods = enabledEntries;
    serverPropertiesFile = serverProperties;
  };

  meta = with lib; {
    description = "magic-vr-pack: magic-focused NeoForge ${minecraftVersion} pack with VR support, prepared server tree for an OCI container";
    license = licenses.unfreeRedistributable;
    platforms = platforms.linux;
  };
}
