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
  {
    # Cooking for Blockheads — kitchen-block + recipe-book mod (oven,
    # fridge, sink, cooking table). Both-sided; registers blocks/items
    # on server, GUI on client. Hard-deps balm >= 21.0.39 (we ship
    # 21.0.56 via the bumps pass). Modrinth-only on NeoForge 1.21.1
    # so client zip drops it under overrides/mods/.
    filename       = "cookingforblockheads-neoforge-1.21.1-21.1.23.jar";
    dropAsOverride = true;
    jar = modrinth "vJnhuDde" "qbBLV6CQ"
      "cookingforblockheads-neoforge-1.21.1-21.1.23.jar"
      "0bag1w4hmd9vmgjmkpzvsfn259am6v2jb6r0dn85jkywfk78qkyi";
  }
  {
    # Tiny Redstone — fits redstone components (gates, repeaters, dust)
    # into a single block-sized panel. Both-sided. NeoForge 21.1+,
    # Modrinth ThvCqQMh. The jar's `forge` filename is misleading —
    # mod metadata declares neoforge.mods.toml, runs natively on
    # NeoForge.
    filename       = "tinyredstone-1.21.1-6.1.3.jar";
    dropAsOverride = true;
    jar = modrinth "ThvCqQMh" "ESelEykG"
      "tinyredstone-1.21.1-6.1.3.jar"
      "1rvyf7ldlbzw0zd4519zy67g7d5ssmghbiq5s2jgcg6ryng33azj";
  }
  {
    # CC: Tweaked — modern fork of ComputerCraft (in-game programmable
    # computers + turtles + monitors via Lua). Both-sided.
    # NeoForge [21.1.9, 21.2), satisfied by 21.1.228. Modrinth gu7yAYhd.
    # Jar filename has "forge" in it because Modrinth historically
    # tagged it that way; the mod metadata is neoforge.mods.toml.
    filename       = "cc-tweaked-1.21.1-forge-1.118.0.jar";
    dropAsOverride = true;
    jar = modrinth "gu7yAYhd" "tufB2KsB"
      "cc-tweaked-1.21.1-forge-1.118.0.jar"
      "1hvd2rj49ksdw2bac0hd26s479x4spd7jmz46l2cpmmx4lvg7xsm";
  }
  {
    # CC:C Bridge — bridges CC: Tweaked with Create. Adds peripherals
    # for reading display boards, item flow, contraptions etc. from Lua.
    # Hard-deps create [6.0.6, 7.0.0) ✓ (we ship 6.0.10) and
    # computercraft >= 1.116.0 ✓ (we ship 1.118.0). Modrinth fXt291FO.
    filename       = "cccbridge-mc1.21.1-v1.7.2-neoforge.jar";
    dropAsOverride = true;
    jar = modrinth "fXt291FO" "k3OVsWus"
      "cccbridge-mc1.21.1-v1.7.2-neoforge.jar"
      "11v67k48wxskb490l8rx25dzdql7p7c3dzza6r70s6hvx9hqj9nc";
  }
  {
    # Advanced Peripherals — adds chat box, energy detector, geo
    # scanner, ME bridge, etc. as CC:T peripherals. Hard-deps
    # computercraft >= 1.116.2 ✓ and neoforge >= 21.1.200 ✓ (we ship
    # 21.1.228). ae2/minecolonies/mekanism deps are optional. Modrinth
    # SOw6jD6x.
    filename       = "AdvancedPeripherals-1.21.1-0.7.61b.jar";
    dropAsOverride = true;
    jar = modrinth "SOw6jD6x" "Q4pvAMQj"
      "AdvancedPeripherals-1.21.1-0.7.61b.jar"
      "12hcnnxdry3fspbsyznnn3bs8mhfy3hsf18f3cjv5if2cd5by089";
  }
  {
    # OpenLoader — auto-loads datapacks/resourcepacks from a global
    # `<game-dir>/openloader/data/` and `<game-dir>/openloader/resources/`
    # folder for every world the server hosts AND every world the
    # client opens in single-player. Lets us bundle datapacks (see
    # ./datapacks.nix) once and have them apply uniformly without
    # per-world manual installation. Modrinth KwWsINvD.
    filename       = "OpenLoader-neoforge-1.21.1-21.1.5.jar";
    dropAsOverride = true;
    jar = modrinth "KwWsINvD" "Szobbnyh"
      "OpenLoader-neoforge-1.21.1-21.1.5.jar"
      "1zs2x1bk11jbiklmvs6dnz6dzb3x4fh2cflxjm72ap6lnaxwmgn0";
  }
  {
    # Lootr — replaces vanilla loot containers with per-player loot
    # tables (each player gets their own roll, dungeon chests aren't
    # exhausted by the first player to open them). NeoForge 21.1.195+
    # ✓ (we ship 21.1.228). Both-sided. Modrinth EltpO5cN (the same
    # mod is on CurseForge but Modrinth is faster + WAF-free).
    filename       = "lootr-neoforge-1.21.1-1.11.37.120.jar";
    dropAsOverride = true;
    jar = modrinth "EltpO5cN" "C2tLycH2"
      "lootr-neoforge-1.21.1-1.11.37.120.jar"
      "13awnrfrw6gfsm13l4hb2kdwvsq84shac2k0n5zi1882dvw0pf7p";
  }
  {
    # Farmer's Delight (vectorwing) — cooking + crops overhaul. Both-
    # sided. NeoForge 21.1.219+ ✓. Optional crafttweaker dep is just
    # for recipe-script hooks; we don't ship crafttweaker but FD
    # boots fine without it. Modrinth R2OftAxM.
    filename       = "FarmersDelight-1.21.1-1.3.1.jar";
    dropAsOverride = true;
    jar = modrinth "R2OftAxM" "9gp7w8NC"
      "FarmersDelight-1.21.1-1.3.1.jar"
      "1x7lcl4mchlgya9d6r5lvmpnlvchnpafxnihp60x85xgjzsznbzh";
  }
  {
    # BetterDays — slows down day/night cycle for longer days. Both-
    # sided. Hard-deps `whitenoise` [2.2.0, 3.0.0) which BetterDays
    # itself JIJ-bundles, so no separate overlay entry needed.
    # Modrinth tPLE214j.
    filename       = "betterdays-1.21.1-3.3.6.3-NEOFORGE.jar";
    dropAsOverride = true;
    jar = modrinth "tPLE214j" "Ho93yCC3"
      "betterdays-1.21.1-3.3.6.3-NEOFORGE.jar"
      "1am29ar8n8n49pgi8if8x5jxjblgmn3kxsvq24v8cpfx6w3avb03";
  }
  {
    # MaFgLib — Masa's Forge/NeoForge library port. Hard-dep of
    # Forgematica (the Litematica NeoForge port below). Client-only:
    # the library wires up keybinds, configuration UIs, and GUI
    # helpers that all reference net.minecraft.client.* classes;
    # loading on a dedicated server triggers RuntimeDistCleaner.
    # Modrinth SKI34J7B.
    filename       = "mafglib-0.4.3+mc1.21.1.jar";
    dropAsOverride = true;
    clientOnly     = true;
    jar = modrinth "SKI34J7B" "CgDQ0u0Q"
      "mafglib-0.4.3%2Bmc1.21.1.jar"
      "10dhm9bgjxl02lqbqf15q62nbraz2cslayx06bi3lr7582nqj1yl";
  }
  {
    # Forgematica — unofficial Litematica NeoForge port by
    # ThinkingStudios. Holographic schematic overlay, area selection,
    # save/load .litematic + vanilla .nbt. Pairs with the in-repo
    # tools/schematic_to_lua.py + builder turtle for designed builds,
    # and with Create's Schematicannon for full-fidelity replay.
    # Hard-deps mafglib (above). Client-only — overlay rendering
    # only, server has nothing to do. Modrinth dCKRaeBC.
    filename       = "forgematica-0.4.1+mc1.21.1.jar";
    dropAsOverride = true;
    clientOnly     = true;
    jar = modrinth "dCKRaeBC" "bNQ9lJbg"
      "forgematica-0.4.1%2Bmc1.21.1.jar"
      "1vzp6pmlks8w4nvvsxcxrl4ns2q5piqbv0gslgp4clqiawrdli3j";
  }
  {
    # More Overlays Updated — restores the JEI double-click-search-
    # highlights-inventory feature (yellow search box) that JEI itself
    # dropped as out-of-scope upstream (mezz/JustEnoughItems#2071).
    # Also adds light-level overlay and mob-spawn indicator. Client-
    # only — pure rendering on top of JEI's GUI. Modrinth Thy5Pqut.
    filename       = "moreoverlays-1.24.2-mc1.21.1-neoforge.jar";
    dropAsOverride = true;
    clientOnly     = true;
    jar = modrinth "Thy5Pqut" "Kq8xaqKi"
      "moreoverlays-1.24.2-mc1.21.1-neoforge.jar"
      "1cf42yrkval08wb53nqcqrdclgljzllvmrfz1k7ybfriksjd3c0s";
  }
  {
    # Vivecraft — VR mod. mods.toml declares `side = "BOTH"` and
    # `displayTest = "IGNORE_SERVER_VERSION"`: the server tolerates
    # the jar (no dist-cleaner trips) and Vivecraft players get
    # full body-tracking propagation when the server has the mod
    # too; non-VR players are unaffected. NeoForge >= 21.0.110 ✓
    # (we ship 21.1.228). Modrinth wGoQDPN5.
    filename       = "vivecraft-1.21.1-1.3.7-neoforge.jar";
    dropAsOverride = true;
    jar = modrinth "wGoQDPN5" "HoNxcbXG"
      "vivecraft-1.21.1-1.3.7-neoforge.jar"
      "1h3sfs3790z6dr8z9v6ybg1cp9ig4khlqlkz1ksp1ha5gxh70xh3";
  }
  {
    # Create Deco — decorative blocks themed around Create's industrial
    # aesthetic (catwalks, railings, brass + iron sheet variants, cage
    # lamps, placards, shipping containers). Both-sided. Declares hard
    # deps on neoforge [21.1.209,) (we ship 21.1.228 ✓), minecraft
    # [1.21.1] ✓, and create [6.0.7, 6.1.0) (we ship 6.0.10 ✓).
    # Modrinth sMvUb4Rb.
    filename       = "createdeco-2.1.3.jar";
    dropAsOverride = true;
    jar = modrinth "sMvUb4Rb" "qrcMVoBD"
      "createdeco-2.1.3.jar"
      "0vhc83ww4a643v5agb0wv5b46q6y1kf505kigmkg3ffn1fnz3b7d";
  }
  {
    # Create: Gears n' Kinetics — expands Create's cogwheel + shaft
    # surface with new cog tiers (small/large/quad/jumbo), beveled
    # gearbox variants, kinetic transmission flavour. Both-sided.
    # Hard deps verified:
    #   neoforge  [21.1.200,)        ✓  (we ship 21.1.228)
    #   minecraft [1.21.1, 1.22)     ✓
    #   create    [6.0.8,)           ✓  (we ship 6.0.10)
    # Modrinth gEWECBVL.
    filename       = "GnKinetics-1.21.1-1.0m.jar";
    dropAsOverride = true;
    jar = modrinth "gEWECBVL" "qr9hMBnj"
      "GnKinetics-1.21.1-1.0m.jar"
      "0fw9217lp5bxbfmms7iswaz0y22bcf4qzf1qs2m68918b6dnjplz";
  }
  {
    # Create: Mixed Casing — right-click any casing/encased block/copycat/
    # conveyor-belt with an ingot or casing plank to swap one half of the
    # casing's recipe (mixed wood+metal variants). Pure aesthetic +
    # logistic flavour. Both-sided. Deps:
    #   minecraft [1.21, )         ✓
    #   create    [6.0.6, 6.1.0)   ✓  (pack ships 6.0.10)
    # Modrinth wMgXLrSd.
    filename       = "create_mixed_casing-1.21.1-1.1.1.jar";
    dropAsOverride = true;
    jar = modrinth "wMgXLrSd" "xo79epr6"
      "create_mixed_casing-1.21.1-1.1.1.jar"
      "0797i75gska9lb9hvs83f1z23p9k5wpa9ngj6lrxyvjs880xxyfp";
  }
  {
    # Colored Crosshair — recolors the vanilla crosshair (and attack /
    # crosshair indicators) to a fixed color. Shipped specifically so the
    # Vivecraft 3D crosshair stays visible in dark caves / nights:
    # Vivecraft uses the vanilla inverse-blend crosshair, which fails when
    # projected onto a near-zero-lit 3D surface. Pre-baked colered-
    # crosshair.json sets color=YELLOW for visibility on both light + dark.
    # Client-only — mod's mods.toml declares side = "CLIENT".
    # Modrinth 8rCFhpfV.
    filename       = "colered-crosshair-neoforge-1.0.3.jar";
    dropAsOverride = true;
    clientOnly     = true;
    jar = modrinth "8rCFhpfV" "9ApByJVD"
      "colered-crosshair-neoforge-1.0.3.jar"
      "1vmvwiyv434jw628gcid3d8c0ns7mf725qlh2jza2l3dkxspcfas";
  }
  {
    # Create: Enchantment Industry — added in -46. Required by Ars Technica
    # compat recipes already present in the Arkana datapack
    # (create_enchantment_industry:grinding/ars_technica/*). Hard deps on
    # create >= 6.0.10 (we ship 6.0.10) and create_dragons_plus >= 1.10.0
    # (we ship 1.10.0b). touhou_little_maid integration optional, skipped.
    filename       = "create-enchantment-industry-2.3.1.jar";
    dropAsOverride = false;
    projectID      = 688768;
    fileID         = 7970748;
    jar = curseforge 7970748 "create-enchantment-industry-2.3.1.jar"
      "0r4h2wjn1x791rmzrgnpb6395rd6dvz853x3kah6h9aqry9h7mkb";
  }

]
