#!/usr/bin/env python3
"""Regenerate arkana-groups.nix from arkana-mods.nix via name-pattern rules.

Usage: ./group-classifier.py > arkana-groups.nix.new && diff arkana-groups.nix arkana-groups.nix.new

Run this after generate-arkana-mods.sh refreshes arkana-mods.nix for a new
Arkana version. Adjust RULES below if Arkana adds mods that don't match
existing patterns; everything unmatched lands in `misc`.
"""
import re
import sys
from pathlib import Path

RULES = [
    # client-only / visual mods — listed in clientOnlyProjectIDs in default.nix.
    # Keeping a regex match here documents what's "really" client-only even
    # though we don't emit a group for them.
    (r'^(sodium|iris-|reeses-sodium|sodiumdynamic|sodiumextras|sodiumleaf|sodiumoptions|flerovium|entity_texture_features|entity_model_features|DistantHorizons|EuphoriaPatcher|ComplementaryReimagined|FreshAnimations|-1\.21\.2 Fresh Moves|FA\+|sounds-|statuseffectbars|blur-|CameraOverhaul|SubtleEffects|visuality|customizableelytra|transmog|immersive_paintings|exposure|gpumemleakfix|alltheleaks|ImmersiveUI)', 'client-or-visual'),

    (r'^(architectury|geckolib|azurelib|CodeChickenLib|balm|framework|jamlib|owo-lib|Placebo|resourcefullib|resourcefulconfig|kotlinforforge|expandability|atlas_api|fzzy_config|midnightlib|txnilib|baguettelib|mru-|ftb-library|accessories|accessorify|accessories_compat_layer|terra_curio|OctoLib|CerbonsAPI|Jupiter|valhelsia_core|lithostitched|moonlight|cupboard|configured|cloth-config|yet_another_config_lib|prickle|Iceberg|attributefix|lionfishapi|Patchouli|fusion|caelus|MidnightLib|jamlib|charmofundying|elytraslot|player-animation-lib|Searchables|PuzzlesLib|Bookshelf|bookshelf|fantasy_armor|amendments|gag-|ferritecore|modernfix|TerraBlender|familiarslib|gtbcs_spell_lib|aces_spell_utils|atlas)', 'core-libs'),
    (r'^(Apotheosis|ApothicAttributes|ApothicEnchanting|ApothicSpawners|apothiccombat|irons_apothic|GatewaysToEternity|Chaotix Apotheotic|ancientreforging|relics-)', 'apothic'),
    (r"^(irons_spellbooks|simplyswords|simplymore|irons_jewelry|alshanex_familiars|gametechbcs_spellbooks|cataclysm_spellbooks|crystal_chronicles|Simply Swords Reforged|reliquified_lenders_cataclysm)", 'irons-spells'),
    (r'^(ars_|Ars Nouveau|not_enough_glyphs|starbunclemania|reliquified_ars_nouveau|aero_additions)', 'ars'),
    (r'^(letsdo-)', 'letsdo'),
    (r'^(DnT-|dungeons-and-taverns|lukis-|takesapillage|ess_requiem|endrem|loot_journal|lootintegrations)', 'dungeons'),
    (r'^(GlitchCore|BiomesOPlenty)', 'glitchfiend'),
    (r'^(handcrafted|immersivelanterns|supplementaries|JadeAddons|Jade-|gravestone|immersive_melodies|pipeorgans|glassential|betterarcheology|hazennstuff|bellsandwhistles|copycats|sophisticated|EnderStorage|ConstructionSticks|gravestonecurioscompat|sophisticatedstoragecreateintegration|sophisticatedbackpackscreateintegration)', 'decor'),
    (r'^(jei-|JustEnoughResources|Controlling|FastFurnace|FastSuite|FastWorkbench|jerintegration|ToastControl|AppleSkin|OverflowingBars|AdvancementPlaques|LegendaryTooltips|polymorph|inventoryessentials|invtweaks|craftingtweaks|light-overlay|Prism|BetterThanMending|NaturesCompass|ExplorersCompass|ExtremeSoundMuffler|BetterThirdPerson|spyglass_improvements|trade-cycling|VisualWorkbench|EasyAnvils|LeavesBeGone|LightOverlay|inventoryessentials|invtweaks|letmedespawn|notrample|rightclickharvest|combat_roll|ftb-chunks|ftb-essentials|ftb-teams|ftb-ultimine|appleskin|Not Enough Recipe Book|spotview)', 'qol'),
    (r'^(bettercombat|BTP-|BetterTridents|BOMD-|cataclysm_weaponery|cataclysmiccombat|L_Ender|fantasy_armor|simplymore|simplyswords|gliders|CutThrough|firesenderexpansion|combat_roll|luckysarmory|luckyswardrobe|armory-conglomery|numismaticoverhaul|darkdoppelganger|gametech)', 'combat'),
    (r'^(aether-|deep_aether|AetherVillages|twilightforest|the_bumblezone|deeperdarker|IceAndFireCE|reliquified_twilight_forest|BEB-|Stellarity|Bumblezone)', 'world'),
    (r'^(create-1\.21\.1|create-aero|sable-|aeronauticscompat|create-new-age|createbigcannons|ritchies|spark-|create_aquatic_ambitions|create_factory_logistics|create_oxidized|create_ultimate_factory|create_wizardry|create-central-kitchen|create-dragons-plus|create-enchantment-industry|createbetterfps|createliquidfuel|createultimine)', 'create-addons'),
]

GROUPS_ORDER = [
    'core-libs', 'apothic', 'irons-spells', 'ars', 'letsdo', 'dungeons',
    'glitchfiend', 'decor', 'qol', 'combat', 'world', 'create-addons',
    'cosmetic', 'food', 'misc',
]

DESCRIPTIONS = {
    'core-libs':    'Library mods many Arkana addons depend on. Architectury, GeckoLib, AzureLib, Placebo, Resourceful Lib, owo-lib, etc. Always enable first when bisecting.',
    'apothic':      "Apotheosis suite (Apotheosis, ApothicAttributes, ApothicEnchanting, ApothicSpawners, ApothicCombat) plus Apoth-adjacent (Gateways to Eternity, Chaotix Apotheotic Tweaks, ancientreforging, relics).",
    'irons-spells': "Iron's Spells 'n Spellbooks family + Simply Swords + Simply More + Iron's Jewelry + spellbook content addons.",
    'ars':          'Ars Nouveau + content addons (ars_creo, ars_elemental, ars_technica, ars_additions, ars_polymorphia, etc.) + reliquified_ars_nouveau.',
    'letsdo':       "Let's Do family — farm_and_charm, candlelight, bakery, brewery, herbalbrews, furniture, API. Tightly coupled internal API; bisect as a single unit.",
    'dungeons':     'Structure / dungeon mods — Dungeons and Taverns, DnT structure overhauls, lukis-* dungeons, end_remastered, loot integration, takes_a_pillage.',
    'glitchfiend':  "GlitchCore + Biomes O' Plenty. Worldgen-heavy, may interact with Aeronautics terrain.",
    'decor':        "Decoration / building mods — Supplementaries, handcrafted, immersive lanterns, sophisticated storage suite, Jade, JEI Tetra-style addons, copycats, EnderStorage.",
    'qol':           "Quality-of-life — JEI, JustEnoughResources, FastFurnace/Suite/Workbench, AppleSkin, AdvancementPlaques, FTB Chunks/Essentials/Teams/Ultimine, NaturesCompass, ExplorersCompass, etc.",
    'combat':        "Combat mods — Better Combat, BetterTridents, L_Ender's Cataclysm, Cataclysm: Weaponry/Combat, BTP, BOMD, gliders, sword/armor mods.",
    'world':         "World / dimension / biome mods — Twilight Forest, Aether, Deep Aether, Bumblezone, Deeper Darker, Ice & Fire CE, Stellarity, BEB.",
    'create-addons': "Arkana-shipped Create addons that aren't part of the Aeronautics floor (Create: Central Kitchen, Dragons+, Enchantment Industry, Factory Logistics, Oxidized, Ultimate Factory, Wizardry, BetterFPS, LiquidFuel, Ultimine, Aquatic Ambitions, Copycats integrations).",
    'cosmetic':      'Cosmetic / visual mods that touch server side (placeholder; most live in client-only).',
    'food':          'Food + farming mods not already in `letsdo` (placeholder).',
    'misc':          'Catch-all bucket — bisect last.',
}


def main():
    here = Path(__file__).parent
    src = (here / 'arkana-mods.nix').read_text()
    entries = re.findall(r'\{\s*projectID\s*=\s*(\d+);.*?filename\s*=\s*"([^"]+)";', src, re.S)

    groups = {k: [] for k in GROUPS_ORDER + ['client-or-visual']}
    for pid, fn in entries:
        for pat, grp in RULES:
            if re.match(pat, fn, re.I):
                groups[grp].append((int(pid), fn))
                break
        else:
            groups['misc'].append((int(pid), fn))

    out = sys.stdout
    out.write("# AUTO-CLASSIFIED — name-pattern grouping of Arkana 1.5's 256 mods.\n")
    out.write("# Patterns live in pkgs/create-arkana-aeronautics-server/group-classifier.py\n")
    out.write("# (regenerate after Arkana version bump). Adjust group membership manually\n")
    out.write("# when bisect surfaces wrong placement (e.g. an Apoth-adjacent mod ending up\n")
    out.write("# in `misc`).\n")
    out.write("#\n")
    out.write("# `enabledArkanaGroups = []` (default) → no Arkana mod gets baked in;\n")
    out.write("# Aeronautics floor (overlays.nix + Create 6.0.10 alwaysInclude) loads alone.\n")
    out.write("{\n")
    for grp in GROUPS_ORDER:
        desc = DESCRIPTIONS[grp]
        pids = sorted({p for p, _ in groups[grp]})
        out.write(f"  {grp} = {{\n")
        out.write(f"    description = \"{desc}\";\n")
        if pids:
            out.write(f"    projectIDs = [\n")
            for p in pids:
                name = next(fn for pp, fn in groups[grp] if pp == p)
                out.write(f"      {p}  # {name}\n")
            out.write(f"    ];\n")
        else:
            out.write(f"    projectIDs = [ ];\n")
        out.write(f"  }};\n\n")
    out.write("}\n")


if __name__ == '__main__':
    main()
