{ stdenvNoCC, lib, fetchurl, unzip, zip, jq, python3, callPackage }:
let
  serverPkg    = callPackage ../create-arkana-aeronautics-server { };
  overlayMods   = import ../create-arkana-aeronautics-server/overlays.nix        { inherit fetchurl stdenvNoCC unzip zip; };
  arkanaExtras  = import ../create-arkana-aeronautics-server/arkana-mods-extras.nix { inherit fetchurl; };
  datapacks     = import ../create-arkana-aeronautics-server/datapacks.nix       { inherit fetchurl stdenvNoCC zip; };
  resourcePacks = import ./resource-packs.nix                                    { inherit lib fetchurl stdenvNoCC unzip zip jq; };

  # ars_nouveau bundles lambdynamiclights-api as JIJ which JPMS-conflicts
  # with the top-level sodiumdynamiclights mod (immersivelanterns hard-deps
  # the latter, so we can't drop that side). Strip the JIJ from
  # ars_nouveau and ship the patched jar in overrides/mods/, dropping the
  # CurseForge manifest entry so the launcher doesn't re-download the
  # bundled version on top.
  arsNouveauReplacement =
    lib.findFirst (m: m.projectID == 401955)
      (throw "client: ars_nouveau replacement (projectID 401955) missing from arkana-mods-extras.nix")
      arkanaExtras.replacements;

  # Supplementaries' `compat.CompatEMFMixin` @Inject is bound to the
  # pre-3.0 EMFModelPartCustom callback signature; EMF 3.0+ added an
  # EMFModelPartRoot parameter and the mixin can't apply. AllTheLeaks
  # 1.1.8's runtime patch covers the EMF range [3.0.0, 3.0.6) but stops
  # there, and any resource pack with JEM models (FreshAnimations etc.)
  # triggers EMF to instantiate EMFModelPartCustom which then triggers
  # the mixin apply → MixinApplyError → crash during model bake.
  # Strip the bad mixin entry from supplementaries-common.mixins.json
  # at build time, ship the patched jar in overrides/mods/, and remove
  # the CurseForge manifest entry so the launcher doesn't re-download
  # an unpatched copy on top.
  supplementariesReplacement =
    lib.findFirst (m: m.projectID == 412082)
      (throw "client: supplementaries replacement (projectID 412082) missing from arkana-mods-extras.nix")
      arkanaExtras.replacements;

  stripFromManifestProjectIDs = [
    arsNouveauReplacement.projectID
    supplementariesReplacement.projectID
  ];
  stripFromManifestProjectIDsJSON = builtins.toJSON stripFromManifestProjectIDs;

  arkanaVersion      = serverPkg.passthru.arkanaVersion;
  aeronauticsVersion = serverPkg.passthru.aeronauticsVersion;
  neoforgeVersion    = serverPkg.passthru.neoforgeVersion;

  version = "${arkanaVersion}+aeronautics-${aeronauticsVersion}";

  arkanaManifestPack = fetchurl {
    url = "https://mediafilez.forgecdn.net/files/6958/271/Create-%20Arkana-1.5.zip";
    name = "Create-Arkana-1.5.zip";
    sha256 = "0zv0ja7ia2d1ivsksf75pqr2q7rkypp0r2y50f0mczmwirbp4dl4";
  };

  # CurseForge launcher resolves manifest entries by (projectID, fileID)
  # and pulls the jar from CurseForge's CDN itself, so for any overlay mod
  # that lives on CurseForge we just append a manifest entry. Modrinth-only
  # mods (Aeronautics, Sable, New Age, spark) can't go through that path
  # — the CurseForge launcher refuses non-CF URLs — so they ship as
  # overrides/mods/<jar>, identical to dragging the jar into the instance
  # by hand.
  curseforgeOverlayEntries =
    builtins.filter (m: !m.dropAsOverride) overlayMods;
  modrinthOverlayEntries =
    builtins.filter (m: m.dropAsOverride) overlayMods;

  # Manifest.json shape for files[]: projectID + fileID + required.
  curseforgeOverlayJSON = builtins.toJSON
    (map (m: {
      projectID = m.projectID;
      fileID    = m.fileID;
      required  = true;
    }) curseforgeOverlayEntries);

  # Replacement directives for fileIDs that the server replaced (cfwidget
  # pagination misses). Client manifest needs the same swap so the
  # CurseForge launcher fetches the version we built against, not the
  # broken older one.
  replacementsJSON = builtins.toJSON
    (map (m: {
      origProjectID = m.origProjectID;
      origFileID    = m.origFileID;
      newProjectID  = m.projectID;
      newFileID     = m.fileID;
    }) arkanaExtras.replacements);

  # Discontinued projectIDs whose manifest entries are stripped entirely
  # (no live file → CurseForge launcher errors on import otherwise).
  skippedJSON = builtins.toJSON
    (map (m: { inherit (m) projectID fileID; }) arkanaExtras.skipped);

  # Disabled projectIDs — server filters these out; client must too,
  # otherwise the launcher installs them and the same registry-init NPEs
  # that crashed the server crash the client. `fileID = null` in the
  # disabled record means "all versions of this projectID"; the manifest
  # filter matches by projectID alone in that case so any pinned fileID
  # in the original Arkana manifest is dropped.
  disabledJSON = builtins.toJSON
    (map (m: {
      projectID = m.projectID;
      fileID    = m.fileID;  # nullable
    }) (arkanaExtras.disabled or [ ]));
in
stdenvNoCC.mkDerivation {
  pname = "create-arkana-aeronautics-client";
  inherit version;

  src = arkanaManifestPack;
  nativeBuildInputs = [ unzip zip jq python3 ];

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

    cd pack

    # Patch the modpack metadata so launchers display the new name + version
    # instead of "Create: Arkana 1.5". Three transformations applied in one
    # jq pass:
    #   1) Drop manifest entries for discontinued mods (skipped) — leaving
    #      them would fail CurseForge launcher import.
    #   2) Swap any (projectID, fileID) that arkana-mods-extras pinned to a
    #      newer file so launcher fetches the version we built against.
    #   3) Append the CurseForge-distributed overlay mods (Big Cannons,
    #      Aeronautics: Compatability, …) to .files.
    # Bump the manifest's loader id to match the server's NeoForge bump.
    # Arkana 1.5 pinned 21.1.206; the server (and many overlay mods)
    # require >= 21.1.219. Without this, the launcher installs 21.1.206
    # and Aeronautics, Sable, simulated, offroad, create, create_new_age,
    # aeronautics_bundled all fail mod-loading with "requires neoforge
    # 21.1.219 or above".
    jq \
      --arg name           "Create: Arkana + Aeronautics" \
      --arg packVersion    "${version}" \
      --arg loaderId       "neoforge-${neoforgeVersion}" \
      --argjson extra      '${curseforgeOverlayJSON}' \
      --argjson replace    '${replacementsJSON}' \
      --argjson skip       '${skippedJSON}' \
      --argjson disabled   '${disabledJSON}' \
      --argjson stripIds   '${stripFromManifestProjectIDsJSON}' \
      '
        .name = $name
        | .version = $packVersion
        | .minecraft.modLoaders |= map(.id = $loaderId)
        | .files |= map(
            . as $f
            | if any($skip[]; .projectID == $f.projectID and .fileID == $f.fileID)
              then empty
              else . end)
        | .files |= map(
            . as $f
            | if any($disabled[];
                .projectID == $f.projectID
                and (.fileID == null or .fileID == $f.fileID))
              then empty
              else . end)
        | .files |= map(
            . as $f
            | if any($stripIds[]; . == $f.projectID)
              then empty
              else . end)
        | .files |= map(
            . as $f
            | (($replace[] | select(.origProjectID == $f.projectID and .origFileID == $f.fileID))
               // null) as $r
            | if $r == null then $f
              else $f + { projectID: $r.newProjectID, fileID: $r.newFileID } end)
        | .files += $extra
      ' \
      manifest.json > manifest.new.json
    mv manifest.new.json manifest.json

    # Pre-baked Distant Horizons config — pin glUploadMode=DATA so M1/M2
    # Mac clients don't crash on GL 4.1 buffer-storage paths. DH merges
    # this partial TOML into its defaults on first run.
    mkdir -p overrides/config
    install -m644 ${./DistantHorizons.toml} overrides/config/DistantHorizons.toml

    # Pre-baked Dark Mode Everywhere config — append "org.vivecraft" to
    # METHOD_SHADER_BLACKLIST so the dark shader doesn't apply to the GUI
    # texture Vivecraft samples for its in-world panel. Without this, VR
    # players see a near-black main menu + nearly-invisible pointer.
    # Non-VR players get the default dark theme (selectedShaderIndex
    # stays at 0).
    install -m644 ${./darkmodeeverywhere-client.toml} overrides/config/darkmodeeverywhere-client.toml

    # Pre-baked Vivecraft client config — bumps seated-mode mouse-edge
    # rotation speed (xSensitivity / ySensitivity) so the Steam Frame +
    # Quest seated-mode workflow doesn't require constant mouse re-grip
    # to turn around. Values are a partial config; Vivecraft's GSON loader
    # fills missing fields with defaults, so any per-player tweaks made
    # in-game are preserved on subsequent saves.
    install -m644 ${./vivecraft-client-config.json} overrides/config/vivecraft-client-config.json

    # Pre-baked Colored Crosshair config — sets crosshair to YELLOW with
    # RED hit highlight so the Vivecraft 3D crosshair stays visible in
    # dark caves. The mod (Modrinth 8rCFhpfV) is shipped via overlays.nix
    # specifically for this use case. File path matches the mod's typo
    # in its config filename ("colered" not "colored").
    install -m644 ${./colered-crosshair.json} overrides/config/colered-crosshair.json

    # Resource Pack Overrides config — read by the Modrinth mod
    # `ResourcePackOverrides` (shipped via overlays.nix) to force the
    # listed mod-bundled built-in packs always-enabled, every launch,
    # regardless of options.txt state. Solves the update-flow case
    # where an existing player already has options.txt from a prior
    # modpack version and our shipped options.txt wouldn't apply.
    # `compatibility: COMPATIBLE` also masks the "wrong MC version"
    # banner for packs that declare pack_format outside 1.21.1's range
    # (subtle_effects targets 1.21.5, supplementaries 1.20.x, etc.) —
    # those packs' content is pure texture/model overrides and works on
    # 1.21.1 fine.
    install -D -m644 ${./resourcepackoverrides.json} \
      overrides/config/resourcepackoverrides.json

    # Pre-populated options.txt with the resource-pack selection that
    # players would otherwise have to enable by hand: the four
    # mod-bundled "optional" built-in packs (Biome Color Water Particles,
    # Darker Ropes, Aether Item Tooltips, Deep Aether Tooltips + Deep
    # Aether Additional Assets). Three of those declare pack_format
    # values outside MC 1.21.1's range (subtle_effects targets 1.21.5+,
    # supplementaries declares 1.20.x, deep_aether tooltips ditto) so
    # they're also listed in `incompatibleResourcePacks` — that's MC's
    # "yes the user really wants these even though they declare wrong
    # version" override. Content is purely texture/model overrides and
    # works on 1.21.1 unchanged.
    #
    # Also pre-binds two keymaps to dodge default-key collisions that
    # closed mod UIs unexpectedly:
    #   - `key.aether.open_accessories.desc` (default I) → unbound.
    #     Aether's "Open/Close Accessories Inventory" stole I from any
    #     focused modded UI (Ars search bar, Create storage filter, …)
    #     so typing the letter I in those UIs popped the accessories
    #     screen and closed the UI.
    #   - `key.relics.active_abilities_list` (default LEFT_ALT) → '.
    #     Relics' HUD-toggle conflicted with Create schematic
    #     positioning, which also uses LEFT_ALT as its modifier key
    #     when placing a schematic. Apostrophe is vanilla-unbound and
    #     not registered by any other mod in this pack.
    # MC fills in defaults on first launch for everything else; players
    # can rebind any of these in-game and the new values stick.
    install -m644 ${./options.txt} overrides/options.txt

    # OpenLoader 21.1.5 ships with an empty `additional_locations` list and
    # only scans config/openloader/packs/, which we don't populate — so the
    # bundled openloader/resources/ + openloader/data/ trees were being
    # ignored on first launch and the player had to enable each resource
    # pack manually in the Options screen. Ship a pre-populated options.json
    # in overrides/config/openloader/ so OL discovers both directories on
    # the very first boot (before it ever writes the default config itself).
    install -D -m644 ${./openloader-options.json} \
      overrides/config/openloader/options.json

    # Pre-baked resource pack(s) → overrides/openloader/resources/.
    # OpenLoader auto-loads zips from <game-dir>/openloader/resources/ at
    # the highest priority, so they override any mod-bundled asset without
    # needing the player to enable a pack in Options → Resource Packs.
    #
    # arkana-vanilla-tag-fixes ships an override of the Sounds mod's
    # sheet_metal.json (replaces #minecraft:cauldrons with explicit block
    # IDs). Sounds reads sheet_metal.json during client ResourceReload —
    # before world datapack tags propagate — so its tag lookup of
    # #minecraft:cauldrons returns empty and LMFT chats the "tags are
    # cooked" alert. Pre-rewriting the asset to explicit cauldron block
    # IDs eliminates the tag query at that early phase.
    mkdir -p overrides/openloader/resources
    arkanaTagFixesPack=${
      stdenvNoCC.mkDerivation {
        name = "arkana-vanilla-tag-fixes-resourcepack";
        src  = ./resourcepacks/arkana-vanilla-tag-fixes;
        nativeBuildInputs = [ zip ];
        buildPhase = ''
          ${zip}/bin/zip -r9 pack.zip . -x '.*' '*/.*'
        '';
        installPhase = ''
          install -m644 pack.zip "$out"
        '';
      }
    }
    install -m644 "$arkanaTagFixesPack" \
      overrides/openloader/resources/arkana-vanilla-tag-fixes-1.0.zip

    # Bundled visual-style resource packs → overrides/openloader/resources/.
    # OpenLoader stacks zips alphabetically (later overrides earlier), so the
    # filename prefixes `01-…` through `04-…` pin the precedence:
    # Stay True → Stay True Compats → Fresh Animations → Create: Fresh Items.
    # arkana-vanilla-tag-fixes-1.0.zip (above) sorts last and therefore wins
    # any sheet_metal.json conflict — that's deliberate; the tag fixes pack
    # *must* be on top because it patches an early-resolution asset.
    ${lib.concatMapStrings (r: ''
      install -m644 "${r.zip}" "overrides/openloader/resources/${r.filename}"
    '') resourcePacks}

    # Bundled datapacks → overrides/openloader/data/. OpenLoader (an
    # overlay mod, see ../create-arkana-aeronautics-server/overlays.nix)
    # auto-loads zips from <game-dir>/openloader/data/ into every
    # single-player world the user creates, mirroring the server-side
    # behaviour without requiring per-world manual install.
    mkdir -p overrides/openloader/data
    ${lib.concatMapStrings (d: ''
      install -m644 "${d.zip}" "overrides/openloader/data/${d.filename}"
    '') datapacks}

    # Drop Modrinth-only overlay jars into overrides/mods/ — the CurseForge
    # launcher copies overrides/ verbatim into the instance after fetching
    # the manifest entries.
    mkdir -p overrides/mods
    ${lib.concatMapStrings (m: ''
      install -m644 "${m.jar}" "overrides/mods/${m.filename}"
    '') modrinthOverlayEntries}

    # ars_nouveau JIJ-stripped (drops bundled lambdynamiclights-api so it
    # no longer JPMS-conflicts with sodiumdynamiclights). The manifest
    # entry for projectID 401955 was filtered above so the launcher
    # doesn't pull the unstripped jar; this overrides/mods/ copy is what
    # ships instead.
    install -m644 "${arsNouveauReplacement.jar}" \
      "overrides/mods/${arsNouveauReplacement.filename}"
    python3 ${../create-arkana-aeronautics-server/strip-lambdynamiclights-jij.py} \
      "overrides/mods/${arsNouveauReplacement.filename}"

    # Supplementaries with compat.CompatEMFMixin stripped from
    # supplementaries-common.mixins.json. The mixin's @Inject targets
    # EMFModelPartCustom with the pre-3.0 EMF callback signature; EMF
    # 3.0+ added an EMFModelPartRoot parameter so mixin apply fails
    # whenever an EMF JEM-model resource pack loads (FreshAnimations,
    # FA+Extensions, etc.). The manifest entry for projectID 412082 was
    # filtered above so the launcher doesn't pull the unpatched jar.
    install -m644 "${supplementariesReplacement.jar}" \
      "overrides/mods/${supplementariesReplacement.filename}"
    chmod +w "overrides/mods/${supplementariesReplacement.filename}"
    python3 ${../create-arkana-aeronautics-server/strip-supplementaries-emf-mixin.py} \
      "overrides/mods/${supplementariesReplacement.filename}"

    # JVM-args guidance ships at the zip root (alongside manifest.json),
    # not under overrides/. CurseForge-style zips treat anything outside
    # overrides/ + manifest.json + modlist.html as informational, so the
    # README is visible to anyone opening the zip but doesn't get extracted
    # into the instance. JVM args can't ride in manifest.json (CF schema
    # has no field for them) — Prism / CF Launcher / MultiMC each need
    # per-launcher steps documented in the README.
    install -m644 ${./JVM-ARGS.md} JVM-ARGS.md

    # README.md at zip root — alongside manifest.json + JVM-ARGS.md.
    # Documents what's in the zip, the pre-baked config overrides we ship
    # for known-issue mods (DarkModeEverywhere + Vivecraft, DH on macOS,
    # EuphoriaPatcher shader version, no-pixie-spam datapack), and how to
    # apply the overrides to an existing instance.
    install -m644 ${./README.md} README.md

    # Repack as a CurseForge-style zip (manifest.json + modlist.html +
    # overrides/) and write it to $out. Importable in the CurseForge
    # launcher, Prism Launcher, and ATLauncher.
    mkdir -p $out
    zip -qr "$out/create-arkana-aeronautics-client-${version}.zip" \
      manifest.json modlist.html JVM-ARGS.md README.md overrides

    runHook postInstall
  '';

  meta = with lib; {
    description = "Create: Arkana + Aeronautics modpack zip (CurseForge-style: manifest.json + overrides/), importable in CurseForge launcher and Prism Launcher";
    homepage = "https://www.curseforge.com/minecraft/modpacks/create-arkana";
    license = licenses.unfreeRedistributable;
  };
}
