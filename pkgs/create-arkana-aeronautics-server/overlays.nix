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
  # ---- Worldgen ----
  {
    # Terralith — datapack-driven biome overhaul (~100 biomes). Replaces
    # the role of BiomesOPlenty since GlitchCore (BoP's required lib) is
    # stuck at 2.1.0.0 for MC 1.21.1 and registry-NPEs under our bumped
    # Create. Terralith is pure data, no Java mod compat surface.
    filename       = "Terralith_1.21.x_v2.5.8.jar";
    dropAsOverride = true;
    jar = modrinth "8oi3bsk5" "MuJMtPGQ"
      "Terralith_1.21.x_v2.5.8.jar"
      "1gr10rhfadigvam24d9dvhmn3q02bs6hj01pm6f7p2y3189klcq0";
  }
  # ---- Server-side performance mods ----
  {
    # C2ME — concurrent chunk management. Parallelizes chunk loading +
    # generation across CPU cores, big win on 4-core pods. Server-only;
    # client tolerates absence.
    filename       = "c2me-neoforge-mc1.21.1-0.3.0+alpha.0.91.jar";
    dropAsOverride = true;
    jar = modrinth "COlSi5iR" "9iPiN34N"
      "c2me-neoforge-mc1.21.1-0.3.0%2Balpha.0.91.jar"
      "0sgk18ksgkwfk4a7v974f31rf0l8d1f5x8qswa706nm0rjrwazhh";
  }
  {
    # Noisium — worldgen perf optimizer. Speeds up biome + structure
    # placement by replacing slow vanilla Java loops with batched ops.
    filename       = "noisium-neoforge-2.3.0+mc1.21-1.21.1.jar";
    dropAsOverride = true;
    jar = modrinth "KuNKN7d2" "nJBE6tif"
      "noisium-neoforge-2.3.0%2Bmc1.21-1.21.1.jar"
      "170h2q2d0c7r7qwkisgvr05aggyzs7zldxwlvv2xf05wjgahjlp9";
  }
  # ScalableLux removed — Sable's mods.toml declares it as a hard
  # incompatibility (`Mod sable is incompatible with scalablelux any`).
  # Aeronautics priority means Sable wins; ScalableLux out.
  {
    # AeroBlender — required by deep_aether (in `world` group). Not in
    # Arkana. Itself hard-deps `aether` + `terrablender` so it can't be
    # always-include — it'd fail the build-time dep check at floor mode
    # where neither lib is present. `requiresGroup = "world"` gates it.
    filename       = "aeroblender-1.21.1-1.0.0-neoforge.jar";
    dropAsOverride = true;
    requiresGroup  = "world";
    jar = modrinth "1eaq94ok" "wSvpPEr3"
      "aeroblender-1.21.1-1.0.0-neoforge.jar"
      "0a4s900665mavmhna5bz4gvvs0zjymwz7mhpj8y58bpfkhq154hn";
  }
  {
    # Common Networking — required by gliders (vc_gliders modId, in
    # `combat` group). Not in Arkana. Self-contained (no upward deps),
    # but no point shipping it without its dependent.
    filename       = "common-networking-neoforge-1.0.21-1.21.1.jar";
    dropAsOverride = true;
    requiresGroup  = "combat";
    jar = modrinth "HIuqnQpi" "pR7AeZk3"
      "common-networking-neoforge-1.0.21-1.21.1.jar"
      "0gjg7shl18agxbga54dr7anckjwbv98jfck712yq81gs2qiwx6r8";
  }
  {
    # Replacement for LeavesBeGone (disabled in arkana-mods-extras —
    # see runtime NPE on Sable's ServerSubLevel chunk init). Rapid Leaf
    # Decay listens to BlockEvent.BreakEvent and walks neighbour leaves
    # for instant decay; purely event-driven, no chunk-init hook, so it
    # doesn't interact with Aeronautics' physics SubLevels at all.
    # Modrinth-only (no CF mirror), so the client zip drops it under
    # overrides/mods/.
    filename       = "RapidLeafDecay-1.21.1-3.0.1.jar";
    dropAsOverride = true;
    jar = modrinth "jSQXzmcf" "5jGrYR7B"
      "RapidLeafDecay-1.21.1-3.0.1.jar"
      "0wlh2awf7xb6avi9dayqb9m8ncps9fzq6hl959bkwl6haa20wffn";
  }
  {
    # Mouse Tweaks — inventory QoL (RMB drag, scroll-wheel item
    # transfer). Client-only; mod's mixins target
    # net.minecraft.client.gui.screens.inventory.AbstractContainerScreen
    # and would fail to load on a dedicated server with dist-cleaner
    # warnings. `clientOnly = true` skips it from the server tree;
    # `dropAsOverride = true` puts the jar into the client zip's
    # overrides/mods/ since Mouse Tweaks is Modrinth-hosted only.
    filename       = "MouseTweaks-neoforge-mc1.21-2.26.1.jar";
    dropAsOverride = true;
    clientOnly     = true;
    jar = modrinth "aC3cM3Vq" "9I21YYxf"
      "MouseTweaks-neoforge-mc1.21-2.26.1.jar"
      "12ycyqsy2d6cxbj3mgx3lrn6k594ap4iawlsj9vppsax3hhg9rk8";
  }
]
