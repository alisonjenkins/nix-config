{ stdenvNoCC, stdenv, lib, fetchurl, unzip, bash, minecraft-modpack-tools
, # Whitelist of Arkana mod groups to bake into the server tree. Default
  # `[]` is the verified Aeronautics-only floor (Aeronautics + Sable +
  # Compatability + New Age + Big Cannons + Ritchie's + spark + JEI). Flip
  # groups on via `.override { enabledArkanaGroups = [ "core-libs" … ]; }`
  # — group names + membership defined in `./arkana-groups.nix`.
  #
  # Why a whitelist instead of "everything minus a strip-list": Arkana 1.5
  # was tuned against Create 6.0.6 + NeoForge 21.1.206, but Aeronautics 1.2.1
  # / Sable / Big Cannons / New Age / Offroad / Simulated all require Create
  # >= 6.0.10 + NeoForge >= 21.1.219. After bumping both, ~12 Arkana addons
  # (Apotheosis, GlitchCore, farm_and_charm, candlelight, bakery,
  # irons_jewelry, waystones, forbidden_arcanus, …) hit `DeferredHolder`
  # registry-init NPEs against the bumped Create. Bisecting which groups
  # boot cleanly is faster than per-mod source patches, and Aeronautics
  # is the user's priority — Arkana content opts in.
  enabledArkanaGroups ? [ ]
}:
let
  # Pack version: <Arkana version>+aeronautics-<Aeronautics version>.
  # Both the docker tag and the on-disk derivation use this.
  version = "1.5+aeronautics-1.2.1";

  # NeoForge loader. Arkana 1.5's manifest pins 21.1.206 but Aeronautics
  # 1.2.1 / Sable / New Age / Offroad / Simulated all require >= 21.1.219
  # at runtime — we bump to the latest 21.1.x stable so every overlay mod
  # loads. Server still negotiates protocol-compatible with 1.21.1 clients
  # because all 21.1.x are protocol-compatible.
  neoforgeVersion = "21.1.228";

  # Arkana ships a CurseForge "manifest pack" — the zip contains
  # manifest.json + overrides/ (configs, shaders) but NO mod jars and NO
  # libraries. We resolve the 259 mods listed in manifest.json into
  # arkana-mods.nix offline (see generate-arkana-mods.sh) and bake them in
  # at build time, then let the NeoForge installer populate libraries/ on
  # the container's first boot.
  arkanaManifestPack = fetchurl {
    url = "https://mediafilez.forgecdn.net/files/6958/271/Create-%20Arkana-1.5.zip";
    name = "Create-Arkana-1.5.zip";
    sha256 = "0zv0ja7ia2d1ivsksf75pqr2q7rkypp0r2y50f0mczmwirbp4dl4";
  };

  # NeoForge server installer. Run by the entrypoint on first boot to
  # populate /data/libraries — Nix's sandbox blocks the installer's network
  # fetches at build time, so we ship the installer jar and defer the
  # install step to runtime (where the k8s pod has outbound network).
  neoforgeInstaller = fetchurl {
    url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/${neoforgeVersion}/neoforge-${neoforgeVersion}-installer.jar";
    name = "neoforge-${neoforgeVersion}-installer.jar";
    sha256 = "1sbzp0s75d0v1r5bcn05dhschrf7sfjnv2j1qqmm2aj94fpdf8si";
  };

  arkanaMods   = import ./arkana-mods.nix        { inherit fetchurl; };
  arkanaExtras = import ./arkana-mods-extras.nix { inherit fetchurl; };
  arkanaGroups = import ./arkana-groups.nix;
  overlayMods  = import ./overlays.nix           { inherit fetchurl; };
  jvmArgs      = import ./jvm-args.nix;

  # Group whitelist: union of all `projectIDs` across enabled groups. An
  # empty list collapses to no Arkana mods, leaving only the overlay
  # (Aeronautics + companions) — that's the verified floor.
  enabledArkanaProjectIDs = lib.concatLists
    (map (g:
      if arkanaGroups ? ${g}
      then arkanaGroups.${g}.projectIDs
      else throw "create-arkana-aeronautics-server: unknown group '${g}' (see arkana-groups.nix)")
      enabledArkanaGroups);

  isInEnabledGroup = m: lib.elem m.projectID enabledArkanaProjectIDs;

  # Replacements (newer versions of mods that broke under bumped Create) and
  # skipped (discontinued, no live file) live in arkana-mods-extras.nix.
  # Disabled mods are mods we've found don't boot even when their group is
  # enabled — kept out unconditionally.
  isReplaced = m: builtins.any
    (r: r.origProjectID == m.projectID && r.origFileID == m.fileID)
    arkanaExtras.replacements;
  isSkipped = m: builtins.any
    (s: s.projectID == m.projectID && s.fileID == m.fileID)
    arkanaExtras.skipped;
  isDisabled = m: builtins.any
    (d: d.projectID == m.projectID && (d.fileID or null == null || d.fileID == m.fileID))
    (arkanaExtras.disabled or [ ]);

  # Build the final mod set: arkana mods that belong to an enabled group
  # AND aren't replaced/skipped/disabled, plus replacements (which are also
  # gated on group membership so an Apotheosis bump doesn't sneak in unless
  # the `apothic` group is on).
  arkanaModsFiltered = builtins.filter
    (m: isInEnabledGroup m && !(isReplaced m) && !(isSkipped m) && !(isDisabled m))
    arkanaMods;
  # Replacements with `alwaysInclude = true` are part of the Aeronautics
  # floor (Create 6.0.10 is the only one today). They install regardless of
  # whether their `origProjectID`'s group is enabled — necessary because
  # the floor has zero Arkana groups but still needs Create.
  enabledReplacements = builtins.filter
    (r: !(isDisabled r) &&
        ((r.alwaysInclude or false) || lib.elem r.origProjectID enabledArkanaProjectIDs))
    arkanaExtras.replacements;
  arkanaModsAll = arkanaModsFiltered ++ enabledReplacements;

  # Mod project IDs that ship in Arkana but are client-only (visual /
  # rendering / shader integration). Stripping them from the server tree
  # avoids spurious mod-handshake warnings AND prevents server crashes
  # when a client-only mixin (e.g. ETF) injects into a class that the
  # dedicated server then loads — the mixin tries to chain-load
  # `net/minecraft/client/gui/screens/Screen` which RuntimeDistCleaner
  # rejects, and the JVM dies in `ResourceLocation.<clinit>`.
  #
  # IDs verified by grepping arkana-mods.nix filenames. Future Arkana bumps
  # that drop one of these turn the strip into a harmless no-op.
  clientOnlyProjectIDs = [
    # JEI (238222) is technically client-only but jeresources declares
    # JEI as a hard server-side dependency, so stripping it crashes the
    # server. Keep JEI in the server tree.
    394468   # Sodium (NeoForge port)
    455508   # Iris Shaders
    508933   # Distant Horizons
    511319   # Reese's Sodium Options
    551736   # Sodium Dynamic Lights
    558905   # Sodium Extras
    568563   # Entity Texture Features (ETF) — the killer in the crash above
    925889   # Sounds (client-only — mixin loads net/minecraft/client/gui/screens/Screen)
    1089479  # Sodium Leaf Culling
    1103431  # Sodium Options API
    1116812  # immersivelanterns — hard-deps sodiumdynamiclights (client-only)
    1142875  # Flerovium (Sodium addon — hard-deps Sodium 0.6.9+)
    1146393  # Sodium Options Mod Compat
    1217518  # createbetterfps — hard-deps Sodium (client-only)
    1284599  # Status Effect Bars (client-only Screen mixin)
  ];

  eulaFile    = builtins.toFile "eula.txt" "eula=true\n";
  jvmArgsFile = builtins.toFile "user_jvm_args.txt" jvmArgs;

  # server.properties is generated fresh because Arkana's manifest pack
  # doesn't ship one — the publisher expects the launcher (or the NeoForge
  # installer) to generate it. We bake a 4-player default tuned for the
  # 4 GiB pod limit; admins can override via the PVC copy on first boot.
  #
  # `level-type=minecraft\:flat` keeps the spawn-prepare phase ~1s instead
  # of 8-15s under biome-rich worldgen. Admins flipping to a survival
  # world should override on the PVC.
  serverProperties = builtins.toFile "server.properties" ''
    server-port=25565
    max-players=4
    view-distance=4
    simulation-distance=2
    motd=Create: Arkana + Aeronautics
    online-mode=true
    enable-rcon=false
    spawn-protection=0
    allow-flight=true
    level-type=minecraft\:flat
  '';
in
stdenvNoCC.mkDerivation {
  pname = "create-arkana-aeronautics-server";
  inherit version;

  # Arkana zip is the structural source (manifest.json + overrides/);
  # everything else is composed in installPhase from the resolved jars.
  src = arkanaManifestPack;
  nativeBuildInputs = [ unzip minecraft-modpack-tools ];

  unpackPhase = ''
    runHook preUnpack
    mkdir -p pack
    unzip -q $src -d pack
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out $out/mods

    # Copy overrides/ (configs, shaderpacks, kubejs scripts) to the server
    # root so per-mod tuning ships with the image. Shaders are harmless on
    # the server but slightly bloat the closure; left in place for parity
    # with the client zip.
    if [ -d pack/overrides ]; then
      cp -r pack/overrides/. $out/
    fi

    # Arkana mods filtered by enabled groups + replacement/skipped/disabled
    # logic above. With `enabledArkanaGroups = []` this list contains only
    # `alwaysInclude` replacements (currently Create 6.0.10).
    # clientOnlyProjectIDs is applied unconditionally — even if a group
    # is enabled that pulls in a Sodium addon, it still gets stripped here
    # because dedicated-server can't load client-only mixins.
    ${lib.concatMapStrings (m:
      if lib.elem m.projectID clientOnlyProjectIDs then ''
        # skip ${toString m.projectID} (${m.filename}) — client-only
      '' else ''
        install -m644 "${m.jar}" "$out/mods/${m.filename}"
      ''
    ) arkanaModsAll}

    # Aeronautics + Sable + companions on top. Each overlay entry may
    # carry `requiresGroup = "<name>"` — if set, the entry only installs
    # when that group is in `enabledArkanaGroups`. Lets us ship libs like
    # AeroBlender (needs deep_aether's chain in `world`) without breaking
    # the floor's pre-flight dep check.
    ${lib.concatMapStrings (m:
      if (m.requiresGroup or null) != null
         && !(lib.elem m.requiresGroup enabledArkanaGroups)
      then ''
        # skip overlay ${m.filename} — requires group "${m.requiresGroup}"
      '' else ''
        install -m644 "${m.jar}" "$out/mods/${m.filename}"
      ''
    ) overlayMods}

    install -m644 ${eulaFile}            $out/eula.txt
    install -m644 ${jvmArgsFile}         $out/user_jvm_args.txt
    install -m644 ${serverProperties}    $out/server.properties
    install -m644 ${neoforgeInstaller}   $out/neoforge-installer.jar

    install -m755 ${./entrypoint.sh}     $out/entrypoint.sh
    # Replace the portable shebang with an absolute store path
    # (dockerTools images contain only /nix/store, no /usr/bin/env)
    # and substitute the libstdc++ path for spark's async-profiler.
    substituteInPlace $out/entrypoint.sh \
        --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash' \
        --replace-fail '@libstdcxxLib@'      '${stdenv.cc.cc.lib}/lib'

    # Pre-flight dep check via minecraft-modpack-tools.dep-tree —
    # parses every jar's META-INF/neoforge.mods.toml (+ JIJ children)
    # and fails the build if any required dep is missing or out-of-range.
    # Saves a ~5 min boot cycle when a regression introduces a missing
    # dep. The tool is generic; see pkgs/minecraft-modpack-tools.
    echo "[deps-check] running dep-tree on $out ..."
    if dep-tree "$out" > $out/.deps-check.log 2>&1; then
      cat $out/.deps-check.log
      if grep -qE '^=== Missing required deps \([1-9]' $out/.deps-check.log; then
        echo "[deps-check] FAIL — missing required deps (see above)" >&2
        exit 1
      fi
      if grep -qE '^=== Required deps out of version range \([1-9]' $out/.deps-check.log; then
        echo "[deps-check] FAIL — version range mismatches (see above)" >&2
        exit 1
      fi
      rm -f $out/.deps-check.log
    else
      cat $out/.deps-check.log >&2
      echo "[deps-check] FAIL — analyzer crashed" >&2
      exit 1
    fi

    runHook postInstall
  '';

  passthru = {
    inherit neoforgeVersion;
    # Surfaced for the client derivation so the manifest version stays in
    # lock-step with the server.
    arkanaVersion = "1.5";
    aeronauticsVersion = "1.2.1";
  };

  meta = with lib; {
    description = "Create: Arkana modpack + Create: Aeronautics 1.2.1, prepared NeoForge 1.21.1 server tree for OCI container";
    homepage = "https://www.curseforge.com/minecraft/modpacks/create-arkana";
    license = licenses.unfreeRedistributable;
    platforms = platforms.linux;
  };
}
