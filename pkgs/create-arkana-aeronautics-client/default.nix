{ stdenvNoCC, lib, fetchurl, unzip, zip, jq, callPackage }:
let
  serverPkg    = callPackage ../create-arkana-aeronautics-server { };
  overlayMods  = import ../create-arkana-aeronautics-server/overlays.nix        { inherit fetchurl; };
  arkanaExtras = import ../create-arkana-aeronautics-server/arkana-mods-extras.nix { inherit fetchurl; };

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
in
stdenvNoCC.mkDerivation {
  pname = "create-arkana-aeronautics-client";
  inherit version;

  src = arkanaManifestPack;
  nativeBuildInputs = [ unzip zip jq ];

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
            | (($replace[] | select(.origProjectID == $f.projectID and .origFileID == $f.fileID))
               // null) as $r
            | if $r == null then $f
              else $f + { projectID: $r.newProjectID, fileID: $r.newFileID } end)
        | .files += $extra
      ' \
      manifest.json > manifest.new.json
    mv manifest.new.json manifest.json

    # Drop Modrinth-only overlay jars into overrides/mods/ — the CurseForge
    # launcher copies overrides/ verbatim into the instance after fetching
    # the manifest entries.
    mkdir -p overrides/mods
    ${lib.concatMapStrings (m: ''
      install -m644 "${m.jar}" "overrides/mods/${m.filename}"
    '') modrinthOverlayEntries}

    # Repack as a CurseForge-style zip (manifest.json + modlist.html +
    # overrides/) and write it to $out. Importable in the CurseForge
    # launcher, Prism Launcher, and ATLauncher.
    mkdir -p $out
    zip -qr "$out/create-arkana-aeronautics-client-${version}.zip" \
      manifest.json modlist.html overrides

    runHook postInstall
  '';

  meta = with lib; {
    description = "Create: Arkana + Aeronautics modpack zip (CurseForge-style: manifest.json + overrides/), importable in CurseForge launcher and Prism Launcher";
    homepage = "https://www.curseforge.com/minecraft/modpacks/create-arkana";
    license = licenses.unfreeRedistributable;
  };
}
