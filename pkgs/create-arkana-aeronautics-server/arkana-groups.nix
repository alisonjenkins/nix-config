# Arkana mod groupings — semantic categories used by the bisection
# workflow. The server derivation accepts `enabledArkanaGroups :: [str]`;
# only mods whose projectID lives in an enabled group's `projectIDs` list
# get baked into the server tree. Default `[]` → Aeronautics floor only.
#
# Groups are populated incrementally as bisection runs. Empty groups are
# valid (placeholders for the bisect script to flip on later). Mods we know
# break — see arkana-mods-extras.nix `disabled = [ ... ]`. Disabled mods
# stay out even when their group is enabled.
#
# To classify a mod: grep its projectID in arkana-mods.nix to see filename,
# then drop the projectID into the matching group below.

{
  core-libs = {
    description = "Library mods many Arkana addons depend on. Architectury, GeckoLib, AzureLib, Placebo, Resourceful Lib, Sophisticated Core, owo-lib, etc. Always enable first when bisecting.";
    projectIDs = [ ];
  };

  apothic = {
    description = "Apotheosis suite (Apotheosis, ApothicAttributes, ApothicEnchanting, ApothicSpawners, ApothicCombat).";
    projectIDs = [ ];
  };

  irons-spells = {
    description = "Iron's Spells 'n Spellbooks + Iron's Gems 'n Jewelry + Spellbooks Patchouli + addons.";
    projectIDs = [ ];
  };

  ars = {
    description = "Ars Nouveau + Ars 'n Spells bridge + content addons.";
    projectIDs = [ ];
  };

  letsdo = {
    description = "Let's Do family — farm_and_charm, candlelight, bakery, brewery, beachparty, vinery, etc. Tightly coupled internal API; bisect as a single unit.";
    projectIDs = [ ];
  };

  dungeons = {
    description = "Structure / dungeon mods — Dungeons and Taverns, YUNG's structures, Repurposed Structures, etc.";
    projectIDs = [ ];
  };

  glitchfiend = {
    description = "GlitchCore + Biomes O' Plenty + Terralith + worldgen relatives.";
    projectIDs = [ ];
  };

  decor = {
    description = "Decoration mods — Supplementaries, Quark, Twigs, Macaw's family.";
    projectIDs = [ ];
  };

  qol = {
    description = "Quality-of-life — Waystones, JEI/JEresources, AppleSkin, Searchables.";
    projectIDs = [ ];
  };

  combat = {
    description = "Better Combat, Apothic Combat, neruina, weapon/armor mods.";
    projectIDs = [ ];
  };

  cosmetic = {
    description = "Accessories, transmog, customizableelytra, cape mods.";
    projectIDs = [ ];
  };

  food = {
    description = "Farmer's Delight + addons not already in `letsdo`.";
    projectIDs = [ ];
  };

  misc = {
    description = "Catch-all bucket for mods that don't fit the other groups. Bisect last.";
    projectIDs = [ ];
  };
}
