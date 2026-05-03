# Mods layered on top of the base Create: Arkana manifest. Imported by both
# the server derivation (where every entry is dropped into mods/) and the
# client derivation (where Modrinth-hosted entries become overrides/mods/
# files because the CurseForge launcher can't follow non-CurseForge URLs in
# manifest.json).
{ fetchurl }:
let
  # Source-of-truth tag: every entry should target Minecraft 1.21.1 NeoForge.
  # Bumping any pin here keeps both the server image and the client zip in
  # sync — they share this single list.
  modrinth = data: versionId: filename: sha256: fetchurl {
    url = "https://cdn.modrinth.com/data/${data}/versions/${versionId}/${filename}";
    name = filename;
    inherit sha256;
  };

  # CurseForge mediafilez splits the file ID into a 4-digit prefix and a
  # 3-digit suffix; spaces and `+` percent-encode in the URL but the on-disk
  # name keeps the raw form (Nix store names disallow `%`).
  curseforge = fileId: filename: sha256:
    let
      prefix = builtins.toString (fileId / 1000);
      suffix = builtins.toString (fileId - (fileId / 1000) * 1000);
      encoded = builtins.replaceStrings [ " " "+" ] [ "%20" "%2B" ] filename;
    in fetchurl {
      url = "https://mediafilez.forgecdn.net/files/${prefix}/${suffix}/${encoded}";
      name = filename;
      inherit sha256;
    };
in
[
  {
    # Aeronautics is Modrinth-only on NeoForge 1.21.1, so the client zip
    # must drop this jar in overrides/mods/ (CurseForge launcher won't fetch
    # a non-CF URL listed in manifest.json).
    filename       = "create-aeronautics-bundled-1.21.1-1.2.1.jar";
    dropAsOverride = true;
    jar = modrinth "oWaK0Q19" "YhZLrAFC"
      "create-aeronautics-bundled-1.21.1-1.2.1.jar"
      "0j32y9aih9xil4fcl51b9ma73jnbmj9kms7jwz77xd61iqb6v32s";
  }
  {
    # Pinned to 1.2.1 (matched-date with Aeronautics 1.2.1) rather than the
    # newer 1.2.2 — Sable's API has churned and Aeronautics ships against the
    # same-day release.
    filename       = "sable-neoforge-1.21.1-1.2.1.jar";
    dropAsOverride = true;
    jar = modrinth "T9PomCSv" "ADGYo8vU"
      "sable-neoforge-1.21.1-1.2.1.jar"
      "0vahdhgymb72mbgbxpb6rnzjg9vgz3yihki71mfjdjlsx2q13h04";
  }
  {
    filename       = "create-new-age-1.1.7c+neoforge-mc1.21.1.jar";
    dropAsOverride = true;
    jar = modrinth "FTeXqI9v" "eQ9rbApE"
      "create-new-age-1.1.7c%2Bneoforge-mc1.21.1.jar"
      "0d4hvf70dpdh1lrmh8fgghjzicfswl844r54i3xwj8dx2dg449gd";
  }
  {
    # Big Cannons IS on CurseForge so the client manifest can reference it
    # by projectID/fileID; the client derivation appends a manifest entry
    # for this jar instead of dropping it into overrides/.
    filename       = "createbigcannons-5.11.3-mc.1.21.1.jar";
    dropAsOverride = false;
    projectID      = 333020;
    fileID         = 8002961;
    jar = curseforge 8002961 "createbigcannons-5.11.3-mc.1.21.1.jar"
      "1pw12ck962wwcayp508nhpmv69b3pfb83v4c2hqq26bk2qf4bjqn";
  }
  {
    filename       = "aeronauticscompat-1.1.2.jar";
    dropAsOverride = false;
    projectID      = 1305471;
    fileID         = 7996938;
    jar = curseforge 7996938 "aeronauticscompat-1.1.2.jar"
      "10k48sqijyqhdvyxq2xazfh8769hv1kdpqmgbw7m5xvil5c83zsy";
  }
  {
    # Spark profiler — small, useful for diagnosing MSPT spikes once Sable
    # physics + 264 mods are running. Server-side analysis only; harmless on
    # client too. Modrinth-hosted, so client override drop.
    filename       = "spark-1.10.124-neoforge.jar";
    dropAsOverride = true;
    jar = modrinth "l6YH9Als" "v5qtqRQi"
      "spark-1.10.124-neoforge.jar"
      "1nqn5r60g3jy80l8irj4nm62vly50vyibfpl3nx4shdymy0qlzk4";
  }
  {
    # Hard dep of createbigcannons (>= 2.1.2). Not in Arkana's manifest.
    filename       = "ritchiesprojectilelib-2.1.2+mc.1.21.1-neoforge.jar";
    dropAsOverride = true;
    jar = modrinth "B3pb093D" "hZ6B2Z0x"
      "ritchiesprojectilelib-2.1.2%2Bmc.1.21.1-neoforge.jar"
      "093v93kwjlf9ly08x7vfrawywziswcf6phx419jzndiphdh90l6c";
  }
]
