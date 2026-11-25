# Mod groups for magic-vr-pack. Every [[mod]] in modlist.toml names one of
# these; generate-mods.py puts resolved dependencies in "core-libs".
#
# `enabledByDefault = false` groups ship only when listed explicitly:
#   magic-vr-pack-server.override { enabledGroups = [ ... "perf-server-optional" ]; }
{
  core-libs = {
    description = "Libraries pulled in as required dependencies of the mods below.";
    enabledByDefault = true;
  };
  magic = {
    description = "Magic progression: Ars Nouveau family, Iron's Spells, Occultism, Malum, Hexerei, Goety and friends.";
    enabledByDefault = true;
  };
  difficulty-bosses = {
    description = "Bosses, dungeon mobs and scaling difficulty (L2 Hostility, Cataclysm, Twilight Forest).";
    enabledByDefault = true;
  };
  worldgen = {
    description = "Terrain, biomes, structures and dimensions.";
    enabledByDefault = true;
  };
  building = {
    description = "Decoration and building tools.";
    enabledByDefault = true;
  };
  programming = {
    description = "ComputerCraft, peripherals and storage networks.";
    enabledByDefault = true;
  };
  vr-client = {
    description = "Vivecraft and VR interaction (client side; Vivecraft also runs on the server for VR player sync).";
    enabledByDefault = true;
  };
  shaders-client = {
    description = "Iris and bundled shader packs.";
    enabledByDefault = true;
  };
  perf-client = {
    description = "Client rendering and memory optimisation.";
    enabledByDefault = true;
  };
  perf-server = {
    description = "Server tick, entity and chunk optimisation.";
    enabledByDefault = true;
  };
  perf-server-optional = {
    description = "Concurrent chunk generation (C2ME alpha). Off by default: alpha build, known mod-compat risk.";
    enabledByDefault = false;
  };
  qol = {
    description = "Quality of life: inventory, tooltips, recipe viewer, backpacks.";
    enabledByDefault = true;
  };
  quests-teams-map = {
    description = "FTB Quests, Teams and Chunks plus Xaero's minimap and world map.";
    enabledByDefault = true;
  };
}
