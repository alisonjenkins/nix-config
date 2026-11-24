{ stdenvNoCC, lib, zip, jq, magic-vr-pack-server }:
let
  server = magic-vr-pack-server;
  inherit (server) version neoforgeVersion minecraftVersion;
  extras = import ../magic-vr-pack-server/extras.nix;

  # The server's group selection and disabled list apply here too, so a mod
  # disabled for crashing the server never reaches players either.
  clientEntries = lib.filter (m: m.side != "server") server.mods;

  # The CurseForge launcher fetches CurseForge files itself and refuses
  # foreign URLs, so Modrinth jars ride in overrides/ instead.
  cfMods = lib.filter (m: m.kind == "mod" && m.source == "curseforge") clientEntries;
  modrinthMods = lib.filter (m: m.kind == "mod" && m.source == "modrinth") clientEntries;
  shaderpacks = lib.filter (m: m.kind == "shaderpack") clientEntries;

  manifest = builtins.toJSON {
    manifestType = "minecraftModpack";
    manifestVersion = 1;
    name = "magic-vr-pack";
    inherit version;
    author = "alisonjenkins";
    overrides = "overrides";
    minecraft = {
      version = minecraftVersion;
      modLoaders = [ { id = "neoforge-${neoforgeVersion}"; primary = true; } ];
    };
    files = map (m: { projectID = m.projectID; fileID = m.fileID; required = true; }) cfMods;
  };

  modlistHtml = ''
    <ul>
    ${lib.concatMapStrings (m: "<li>${lib.escapeXML m.title} (${lib.escapeXML m.version})</li>\n")
      (lib.sort (a: b: a.title < b.title) (lib.filter (m: m.kind == "mod") clientEntries))}</ul>
  '';
in
stdenvNoCC.mkDerivation {
  pname = "magic-vr-pack-client";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  nativeBuildInputs = [ zip jq ];

  passAsFile = [ "manifest" "modlistHtml" ];
  inherit manifest modlistHtml;

  installPhase = ''
    runHook preInstall

    mkdir -p pack/overrides/mods pack/overrides/shaderpacks pack/overrides/config
    cd pack

    jq . "$manifestPath" > manifest.json
    cp "$modlistHtmlPath" modlist.html

    ${lib.concatMapStrings (m: ''
      install -m644 "${m.jar}" "overrides/mods/${m.filename}"
    '') modrinthMods}
    ${lib.concatMapStrings (m: ''
      install -m644 "${m.jar}" "overrides/shaderpacks/${m.filename}"
    '') shaderpacks}

    # Keeps LODs behind cave ceilings.
    install -m644 ${./DistantHorizons.toml} overrides/config/DistantHorizons.toml
    # Faster seated-mode mouse-edge turning; partial config, GSON fills the rest.
    install -m644 ${./vivecraft-client-config.json} overrides/config/vivecraft-client-config.json
    # File name matches the mod's own typo ("colered").
    install -m644 ${./colered-crosshair.json} overrides/config/colered-crosshair.json
    # Same book as the server, so single-player worlds get it too.
    cp -r ${server}/config/ftbquests overrides/config/
    chmod -R u+w overrides/config/ftbquests
    # Same L2 Hostility settings as the server, for single-player worlds.
    install -Dm644 ${server}/config/l2configs/l2hostility-server.toml overrides/config/l2configs/l2hostility-server.toml

    install -m644 ${./JVM-ARGS.md} JVM-ARGS.md
    install -m644 ${./README.md} README.md

    mkdir -p $out
    zip -qr "$out/magic-vr-pack-client-${version}.zip" \
      manifest.json modlist.html JVM-ARGS.md README.md overrides

    runHook postInstall
  '';

  passthru = {
    inherit cfMods modrinthMods shaderpacks;
    omitted = extras.omitted;
  };

  meta = with lib; {
    description = "magic-vr-pack client zip (CurseForge-style manifest.json + overrides/), importable in Prism and the CurseForge launcher";
    license = licenses.unfreeRedistributable;
  };
}
