# AUTO-CLASSIFIED — name-pattern grouping of Arkana 1.5's 256 mods.
# Patterns live in pkgs/create-arkana-aeronautics-server/group-classifier.py
# (regenerate after Arkana version bump). Adjust group membership manually
# when bisect surfaces wrong placement (e.g. an Apoth-adjacent mod ending up
# in `misc`).
#
# `enabledArkanaGroups = []` (default) → no Arkana mod gets baked in;
# Aeronautics floor (overlays.nix + Create 6.0.10 alwaysInclude) loads alone.
{
  core-libs = {
    description = "Library mods many Arkana addons depend on. Architectury, GeckoLib, AzureLib, Placebo, Resourceful Lib, owo-lib, etc. Always enable first when bisecting.";
    projectIDs = [
      228525  # bookshelf-neoforge-1.21.1-21.1.68.jar
      242818  # CodeChickenLib-1.21.1-4.6.1.524.jar
      280510  # attributefix-neoforge-1.21.1-21.1.2.jar
      283644  # Placebo-1.21.1-9.9.1.jar
      306770  # Patchouli-1.21.1-92-NEOFORGE.jar
      308989  # caelus-neoforge-7.0.1+1.21.1.jar
      309927  # curios-neoforge-9.5.1+1.21.1.jar
      316873  # charmofundying-neoforge-9.1.0+1.21.1.jar
      317716  # elytraslot-neoforge-9.0.2+1.21.1.jar
      326652  # cupboard-1.21-2.9.jar
      348521  # cloth-config-15.0.140-neoforge.jar
      351264  # kotlinforforge-5.9.0-all.jar
      388172  # geckolib-neoforge-1.21.1-4.7.7.jar
      404465  # ftb-library-neoforge-2101.1.19.jar
      416935  # valhelsia_core-neoforge-1.21.1-1.1.5.jar
      419699  # architectury-13.0.8-neoforge.jar
      429235  # ferritecore-7.0.2-neoforge.jar
      457570  # configured-neoforge-1.21.1-2.6.0.jar
      465066  # expandability-12.0.0.jar
      488090  # midnightlib-1.7.5-neoforge+1.21.1.jar
      495476  # PuzzlesLib-v21.1.38-1.21.1-NeoForge.jar
      499980  # moonlight-1.21-2.22.6-neoforge.jar
      520110  # Iceberg-1.21.1-neoforge-1.3.2.jar
      531761  # balm-neoforge-1.21.1-21.0.49.jar
      532610  # owo-lib-neoforge-0.12.15.5-beta.1+1.21.jar
      549225  # framework-neoforge-1.21.1-0.9.6.jar
      570073  # resourcefullib-neoforge-1.21-3.0.12.jar
      623764  # jamlib-neoforge-1.3.5+1.21.1.jar
      658587  # player-animation-lib-forge-2.0.1+1.21.1.jar
      667299  # yet_another_config_lib_v3-3.7.1+1.21.1-neoforge.jar
      669659  # mru-1.0.19+LTS+1.21.1+neoforge.jar
      694962  # gag-5.1.1.jar
      714059  # resourcefulconfig-neoforge-1.21-3.0.11.jar
      790626  # modernfix-neoforge-5.24.3+mc1.21.1.jar
      817423  # azurelib-neo-1.21.1-3.0.27.jar
      854949  # fusion-1.2.11a-neoforge-mc1.21.jar
      858542  # Searchables-neoforge-1.21.1-1.0.2.jar
      896746  # amendments-1.21-2.0.5-neoforge.jar
      916747  # OctoLib-NEOFORGE-0.6.0.4+1.21.jar
      936015  # lithostitched-neoforge-1.21.1-1.4.11.jar
      938917  # accessories-neoforge-1.1.0-beta.49+1.21.1.jar
      940057  # TerraBlender-neoforge-1.21.1-4.1.0.8.jar
      955605  # CerbonsAPI-NeoForge-1.21-1.3.0.jar
      1005914  # fzzy_config-0.7.2+1.21+neoforge.jar
      1023259  # prickle-neoforge-1.21.1-21.1.10.jar
      1027625  # terra_curio-1.1.2.jar
      1072905  # Jupiter-2.2.2-neoforge.jar
      1083998  # fantasy_armor-1.1.1-1.21.1.jar
      1104882  # txnilib-neoforge-1.0.24-1.21.1.jar
      1145462  # atlas_api-1.21.1-1.2.0.jar
      1169634  # accessorify-2.2.0+1.21.1.jar
      1264423  # baguettelib-1.21.1-NeoForge-1.1.0.jar
      1315611  # accessories_compat_layer-neoforge-0.1.6+1.21.1.jar
    ];
  };

  apothic = {
    description = "Apotheosis suite (Apotheosis, ApothicAttributes, ApothicEnchanting, ApothicSpawners, ApothicCombat) plus Apoth-adjacent (Gateways to Eternity, Chaotix Apotheotic Tweaks, ancientreforging, relics).";
    projectIDs = [
      313970  # Apotheosis-1.21.1-8.4.0.jar
      417802  # GatewaysToEternity-1.21.1-5.1.0.jar
      445274  # relics-1.21.1-0.10.7.6.jar
      898963  # ApothicAttributes-1.21.1-2.9.0.jar
      970522  # Chaotix Apotheotic Tweaks v2.0 1.21.1.zip
      985468  # ancientreforging-1.8.jar
      986583  # ApothicSpawners-1.21.1-1.3.2.jar
      986982  # apothiccombat-1.2.1.jar
      1063926  # ApothicEnchanting-1.21.1-1.5.0.jar
      1244863  # irons_apothic-1.7.3.jar
    ];
  };

  irons-spells = {
    description = "Iron's Spells 'n Spellbooks family + Simply Swords + Simply More + Iron's Jewelry + spellbook content addons.";
    projectIDs = [
      659887  # simplyswords-neoforge-1.61.3-1.21.1.jar
      855414  # irons_spellbooks-1.21.1-3.14.3.jar
      1095252  # simplymore-forge-1.2.0.jar
      1098749  # Simply Swords Reforged v1.zip
      1099461  # cataclysm_spellbooks-1.1.9-1.21.jar
      1101111  # irons_jewelry-1.21.1-1.5.2.jar
      1125198  # gametechbcs_spellbooks-3.0.0-1.21.1.jar
      1153374  # crystal_chronicles-0.0.7-alpha.jar
      1171602  # alshanex_familiars-1.21.1_v3.0.jar
      1194714  # gtbcs_spell_lib-1.0.1-1.21.1.jar
      1232116  # reliquified_lenders_cataclysm-1.21.1-0.1.1.jar
      1299492  # aces_spell_utils-1.1.7-1.21.1.jar
      1316458  # familiarslib-1.0.0.jar
    ];
  };

  ars = {
    description = "Ars Nouveau + content addons (ars_creo, ars_elemental, ars_technica, ars_additions, ars_polymorphia, etc.) + reliquified_ars_nouveau.";
    projectIDs = [
      401955  # ars_nouveau-1.21.1-5.10.4.jar
      561470  # ars_elemental-1.21.1-0.7.5.0.1.jar
      575698  # ars_creo-1.21.1-5.1.0.jar
      746215  # starbunclemania-1.21.1-1.4.0.1.jar
      974408  # ars_additions-1.21.1-21.2.3.jar
      1023517  # not_enough_glyphs-1.21.1-4.2.2.0.jar
      1061812  # ars_controle-1.21.1-1.6.9.jar
      1080571  # Ars Nouveau Refresh 1.2.0.zip
      1096161  # ars_technica-1.21.1-2.3.0.jar
      1153666  # ars_elemancy-1.21.1-1.10.jar
      1160104  # aero_additions-1.2.4.jar
      1196449  # reliquified_ars_nouveau-1.21.1-0.6.1.jar
      1197614  # ars_polymorphia-1.0.3.jar
    ];
  };

  letsdo = {
    description = "Let's Do family — farm_and_charm, candlelight, bakery, brewery, herbalbrews, furniture, API. Tightly coupled internal API; bisect as a single unit.";
    projectIDs = [
      864599  # letsdo-API-forge-1.3.0-beta-release-forge.jar
      951221  # letsdo-herbalbrews-neoforge-1.1.0.jar
      1038103  # letsdo-farm_and_charm-neoforge-1.1.3.jar
      1038106  # letsdo-brewery-neoforge-2.1.1.jar
      1038117  # letsdo-candlelight-neoforge-2.1.0.jar
      1038130  # letsdo-bakery-neoforge-2.1.0.jar
      1062363  # letsdo-furniture-neoforge-1.1.0.jar
    ];
  };

  dungeons = {
    description = "Structure / dungeon mods — Dungeons and Taverns, DnT structure overhauls, lukis-* dungeons, end_remastered, loot integration, takes_a_pillage.";
    projectIDs = [
      404183  # endrem-neoforge-1.21.X-6.0.2.jar
      580689  # lootintegrations-1.21.1-4.7.jar
      853794  # dungeons-and-taverns-v4.4.4 [NeoForge].jar
      920418  # DnT-ancient-city-overhaul-v2 [NeoForge].jar
      920423  # DnT-pillager-outpost-overhaul-v2.2 [NeoForge].jar
      920439  # DnT-swamp-hut-overhaul-v2 [NeoForge].jar
      1003666  # lukis-grand-capitals-1.1.2.jar
      1053222  # DnT-woodland-mansion-replacement-v1.2 [NeoForge].jar
      1053225  # DnT-desert-temple-replacement-v1.2 [NeoForge].jar
      1053226  # DnT-jungle-temple-replacement-v1.2 [NeoForge].jar
      1053227  # DnT-ocean-monument-replacement-v1.2 [NeoForge].jar
      1053229  # DnT-nether-fortress-overhaul-v2.4 [NeoForge].jar
      1059409  # DnT-end-castle-standalone-v1.1 [NeoForge].jar
      1082929  # lukis-crazy-chambers-1.0.2.jar
      1111063  # takesapillage-neoforge-1.0.9+mc1.21.1.jar
      1120395  # loot_journal-neoforge-1.21.1-4.0.1.jar
      1130800  # lootintegrations_betterarcheology-1.2.jar
      1134260  # lootintegrations_cataclysm-1.1.jar
      1139414  # lootintegrations_dnt-2.4.jar
      1269720  # lootintegrations_stellarity-1.0.jar
      1336977  # ess_requiem-0.0.3.jar
    ];
  };

  glitchfiend = {
    description = "GlitchCore + Biomes O' Plenty. Worldgen-heavy, may interact with Aeronautics terrain.";
    projectIDs = [
      220318  # BiomesOPlenty-neoforge-1.21.1-21.1.0.12.jar
      955399  # GlitchCore-neoforge-1.21.1-2.1.0.0.jar
    ];
  };

  decor = {
    description = "Decoration / building mods — Supplementaries, handcrafted, immersive lanterns, sophisticated storage suite, Jade, JEI Tetra-style addons, copycats, EnderStorage.";
    projectIDs = [
      238551  # gravestone-neoforge-1.21.1-1.0.33.jar
      245174  # EnderStorage-1.21.1-2.13.0.191.jar
      324717  # Jade-1.21.1-NeoForge-15.10.3.jar
      412082  # supplementaries-1.21-3.4.13-neoforge.jar
      422301  # sophisticatedbackpacks-1.21.1-3.24.21.1314.jar
      538214  # handcrafted-neoforge-1.21.1-4.0.3.jar
      583345  # JadeAddons-1.21.1-NeoForge-6.1.0.jar
      618298  # sophisticatedcore-1.21.1-1.3.65.1096.jar
      619320  # sophisticatedstorage-1.21.1-1.4.50.1235.jar
      835687  # betterarcheology-neoforge-1.3.2.jar
      904471  # immersive_melodies-neoforge-0.6.2+1.21.1.jar
      905040  # bellsandwhistles-0.4.7-1.21.1.jar
      945149  # Glassential-renewed-neoforge-1.21.1-3.2.2.jar
      968398  # copycats-3.0.2+mc.1.21.1-neoforge.jar
      1116812  # immersivelanterns-neoforge-1.0.6-1.21.1.jar
      1139062  # gravestonecurioscompat-1.21.1-NeoForge-3.0.1.jar
      1156098  # ConstructionSticks-1.21.1-1.2.3.jar
      1196142  # pipeorgans-0.6.4+1.21.1.jar
      1226755  # sophisticatedstoragecreateintegration-1.21.1-0.1.11.37.jar
      1231627  # hazennstuff-1.2.0.jar
      1238567  # sophisticatedbackpackscreateintegration-1.21.1-0.1.3.13.jar
    ];
  };

  qol = {
    description = "Quality-of-life — JEI, JustEnoughResources, FastFurnace/Suite/Workbench, AppleSkin, AdvancementPlaques, FTB Chunks/Essentials/Teams/Ultimine, NaturesCompass, ExplorersCompass, etc.";
    projectIDs = [
      233071  # craftingtweaks-neoforge-1.21.1-21.1.6.jar
      238222  # jei-1.21.1-neoforge-19.21.2.313.jar
      240630  # JustEnoughResources-NeoForge-1.21.1-1.6.0.17.jar
      248787  # appleskin-neoforge-mc1.21-3.0.7.jar
      250398  # Controlling-neoforge-1.21.1-19.0.5.jar
      252848  # NaturesCompass-1.21.1-3.0.3-neoforge.jar
      264738  # BetterThanMending-2.2.0.jar
      271740  # ToastControl-1.21.1-9.0.1.jar
      288885  # FastWorkbench-1.21.1-9.1.3.jar
      299540  # FastFurnace-1.21.1-9.0.1.jar
      314906  # ftb-chunks-neoforge-2101.1.10.jar
      325492  # light-overlay-12.0.0-neoforge.jar
      363363  # ExtremeSoundMuffler-3.51_NeoForge-1.21.jar
      368825  # inventoryessentials-neoforge-1.21.1-21.1.4.jar
      386134  # ftb-ultimine-neoforge-2101.1.9.jar
      388800  # polymorph-neoforge-1.1.0+1.21.1.jar
      404468  # ftb-teams-neoforge-2101.1.4.jar
      410811  # ftb-essentials-neoforge-2101.1.6.jar
      435044  # BetterThirdPerson-neoforge-1.9.0.jar
      452834  # rightclickharvest-neoforge-4.5.3+1.21.1.jar
      475117  # FastSuite-1.21.1-6.0.5.jar
      491794  # ExplorersCompass-1.21.1-3.0.3-neoforge.jar
      499826  # AdvancementPlaques-1.21.1-neoforge-1.6.8.jar
      500273  # VisualWorkbench-v21.1.1-1.21.1-NeoForge.jar
      506948  # jerintegration-6.5.0.jar
      532127  # LegendaryTooltips-1.21.1-neoforge-1.5.5.jar
      570431  # trade-cycling-neoforge-1.21.1-1.0.18.jar
      571264  # spyglass_improvements-1.5.7+mc1.21+neoforge.jar
      638111  # Prism-1.21.1-neoforge-1.0.11.jar
      663477  # letmedespawn-1.21.x-neoforge-1.5.0.jar
      678036  # combat_roll-neoforge-2.0.5+1.21.1.jar
      682567  # EasyAnvils-v21.1.0-1.21.1-NeoForge.jar
      686435  # LeavesBeGone-v21.1.0-1.21.1-NeoForge.jar
      738663  # Not Enough Recipe Book-NEOFORGE-0.4.3+1.21.jar
      852662  # OverflowingBars-v21.1.1-1.21.1-NeoForge.jar
      914018  # notrample-1.21.1-1.0.1.jar
      976858  # invtweaks-1.21.1-1.3.2.jar
    ];
  };

  combat = {
    description = "Combat mods — Better Combat, BetterTridents, L_Ender's Cataclysm, Cataclysm: Weaponry/Combat, BTP, BOMD, gliders, sword/armor mods.";
    projectIDs = [
      551586  # L_Ender's Cataclysm 1.21.1-3.16.jar
      639842  # bettercombat-neoforge-2.2.4+1.21.1.jar
      666941  # BetterTridents-v21.1.0-1.21.1-NeoForge.jar
      792975  # cataclysm_weaponery-3.0.0-neoforge-1.21.1.jar
      828331  # gliders-1.21.1-neoforge-1.1.8.jar
      880483  # cataclysmiccombat-1.4.1.jar
      892893  # armory-conglomery-v2.1.zip
      941573  # BOMD-NeoForge-1.21-1.3.2.jar
      968067  # luckyswardrobe-2.0.0.jar
      969423  # CutThrough-v21.1.0-1.21.1-NeoForge.jar
      1007669  # luckysarmory-1.0.1.jar
      1110803  # darkdoppelganger-3.1.6-1.21.1.jar
      1245989  # firesenderexpansion-2.1.4.jar
      1294551  # numismaticoverhaul-1.21.1-2.0.1.jar
      1298070  # BTP-NeoForge-1.21.1-1.0.2.jar
    ];
  };

  world = {
    description = "World / dimension / biome mods — Twilight Forest, Aether, Deep Aether, Bumblezone, Deeper Darker, Ice & Fire CE, Stellarity, BEB.";
    projectIDs = [
      227639  # twilightforest-1.21.1-4.7.3196-universal.jar
      255308  # aether-1.21.1-1.5.9-neoforge.jar
      362479  # the_bumblezone-7.10.2+1.21.1-neoforge.jar
      659011  # deeperdarker-neoforge-1.21.1-1.3.5.jar
      852465  # deep_aether-1.21.1-1.1.4.jar
      883166  # Stellarity-3.0.6.1.jar
      1040076  # IceAndFireCE-2.0-beta.4-1.21.1-neoforge.jar
      1073197  # AetherVillages-1.21.1-1.0.8-neoforge.jar
      1083202  # BEB-NeoForge-1.21-5.0.0.jar
      1186617  # reliquified_twilight_forest-1.21.1-0.5.2.jar
    ];
  };

  create-addons = {
    description = "Arkana-shipped Create addons that aren't part of the Aeronautics floor (Create: Central Kitchen, Dragons+, Enchantment Industry, Factory Logistics, Oxidized, Ultimate Factory, Wizardry, BetterFPS, LiquidFuel, Ultimine, Aquatic Ambitions, Copycats integrations).";
    projectIDs = [
      328085  # create-1.21.1-6.0.6.jar
      688768  # create-enchantment-industry-2.2.0.jar
      820977  # create-central-kitchen-2.1.3.jar
      840734  # createliquidfuel-2.1.1-1.21.1.jar
      949995  # create_wizardry-0.2.7.jar
      953729  # create_oxidized-0.1.3.jar
      978125  # create_ultimate_factory-2.1.1-neoforge-1.21.1.jar
      1005676  # create_aquatic_ambitions-1.21.1-2.0.1.jar
      1216624  # create-dragons-plus-1.7.0.jar
      1217518  # createbetterfps-1.21.1-1.1.1.jar
      1218807  # create_factory_logistics-1.21.1-1.4.7.jar
      1231381  # createultimine-1.21.1-neoforge-1.2.1.jar
    ];
  };

  cosmetic = {
    description = "Cosmetic / visual mods that touch server side (placeholder; most live in client-only).";
    projectIDs = [ ];
  };

  food = {
    description = "Food + farming mods not already in `letsdo` (placeholder).";
    projectIDs = [ ];
  };

  misc = {
    description = "Catch-all bucket — bisect last.";
    projectIDs = [
      245755  # waystones-neoforge-1.21.1-21.1.22.jar
      254268  # torchmaster-neoforge-1.21.1-21.1.5-beta.jar
      309858  # forbidden_arcanus-2.6.1.jar
      448233  # entityculling-neoforge-1.8.2-mc1.21.jar
      574123  # darkmodeeverywhere-1.21-1.3.5.jar
      655619  # better_climbing-neoforge-4.jar
      656346  # lmft-1.0.4+1.21-neoforge.jar
      851046  # Neruina-2.2.11-neoforge+1.21.jar
      897858  # bobberdetector-neoforge1.21.1-1.0.3.jar
      951287  # arcane_abilities-0.2.8.jar
      1010827  # uranus-2.3.2-1.21.1-neoforge.jar
      1115285  # almanac-1.21.x-neoforge-1.0.2.jar
      1272655  # dynamic_difficulty-0.5.0.jar
    ];
  };

}
