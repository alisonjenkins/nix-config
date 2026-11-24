#!/usr/bin/env python3
"""Generate the magic-vr-pack FTB Quests book.

Usage:
  gen.py OUT_DIR          write config/ftbquests/quests/ into OUT_DIR
  gen.py --dump-outline   print slug|title|plain for every quest, chapter and table

Quest text comes in two parts: an in-character line by Archmage Veyla from
lore.json (keyed by slug), and the plain instruction written here. The
generator fails if a slug has no lore line, so the two files stay in step.

IDs are derived from slugs, so re-running the generator keeps every quest's
ID stable and players keep their progress across pack updates. Rename a slug
and that quest's progress resets.
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ---------------------------------------------------------------- SNBT ----


class L(int):
    """SNBT long: 5L."""


class D(float):
    """SNBT double: 1.5d."""


class F(float):
    """SNBT float: 2.0f."""


BARE_KEY = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.+")


def snbt_str(s):
    if any(ord(c) < 0x20 for c in s):
        raise ValueError(f"control character in SNBT string: {s!r}")
    return json.dumps(s, ensure_ascii=False)


def snbt_key(k):
    return k if k and set(k) <= BARE_KEY else snbt_str(k)


def snbt(v, ind=0):
    pad = "\t" * (ind + 1)
    end = "\t" * ind
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, L):
        return f"{int(v)}L"
    if isinstance(v, D):
        return f"{float(v)}d"
    if isinstance(v, F):
        return f"{float(v)}f"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return snbt_str(v)
    if isinstance(v, dict):
        if not v:
            return "{ }"
        body = "\n".join(f"{pad}{snbt_key(k)}: {snbt(v[k], ind + 1)}" for k in sorted(v))
        return "{\n" + body + "\n" + end + "}"
    if isinstance(v, (list, tuple)):
        if not v:
            return "[ ]"
        return "[\n" + "\n".join(pad + snbt(x, ind + 1) for x in v) + "\n" + end + "]"
    raise TypeError(f"cannot write {type(v).__name__} as SNBT")


# ----------------------------------------------------------------- IDs ----

_seen_ids = {}


def hid(key):
    n = int.from_bytes(hashlib.sha256(key.encode()).digest()[:8], "big") & 0x7FFF_FFFF_FFFF_FFFF
    h = f"{n:016X}"
    if h == "0000000000000001":
        raise ValueError(f"{key}: hashes to the reserved file ID")
    if _seen_ids.setdefault(h, key) != key:
        raise ValueError(f"ID collision: {key} and {_seen_ids[h]}")
    return h


def item(spec):
    """'ns:id' or 'ns:id*N' -> (id, count)."""
    iid, _, n = spec.partition("*")
    return iid, int(n or 1)


# ------------------------------------------------------- reward tables ----

ACT_XP = {0: 50, 1: 100, 2: 200, 3: 400, 4: 800, "side": 75}


class Table:
    all = {}

    def __init__(self, slug, title, act, entries, icon, crate=None, loot_size=1):
        self.slug, self.title, self.act = slug, title, act
        self.entries, self.icon, self.crate, self.loot_size = entries, icon, crate, loot_size
        self.id = hid(f"table:{slug}")
        Table.all[slug] = self

    def snbt(self, order):
        rewards = []
        for i, (spec, weight) in enumerate(self.entries):
            iid, n = item(spec)
            r = {"id": hid(f"entry:{self.slug}:{i}"), "item": {"count": n, "id": iid}, "type": "item"}
            if weight != 1:
                r["weight"] = F(weight)
            rewards.append(r)
        d = {
            "filename": self.slug,
            "id": self.id,
            "loot_size": self.loot_size,
            "order_index": order,
            "rewards": rewards,
        }
        if self.crate:
            name, color = self.crate
            d["hide_tooltip"] = True
            d["icon"] = {"components": {"ftbquests:loot_crate": self.slug}, "id": "ftbquests:lootcrate"}
            d["loot_crate"] = {
                "color": color,
                "drops": {"boss": 0, "monster": 0, "passive": 0},
                "glow": True,
                "item_name": name,
                "string_id": self.slug,
            }
        else:
            d["icon"] = {"id": self.icon}
        return d


def tables():
    T = Table
    # Loot crates, one per act. Contents never reach past their own act.
    T("hearthstone", "Hearthstone Crate", 0, [
        ("minecraft:bread*8", 3), ("minecraft:iron_ingot*6", 3), ("minecraft:torch*32", 3),
        ("waystones:warp_scroll*2", 2), ("minecraft:experience_bottle*8", 2),
        ("farmersdelight:rope*16", 2), ("minecraft:cooked_beef*8", 2),
    ], "minecraft:chest", crate=("Hearthstone Crate", "#C98B4A"))
    T("spark", "Spark Crate", 1, [
        ("ars_nouveau:source_gem*8", 3), ("irons_spellbooks:arcane_essence*8", 3),
        ("irons_spellbooks:common_ink*4", 2), ("hexerei:selenite_shard*6", 2),
        ("minecraft:lapis_lazuli*16", 3), ("minecraft:amethyst_shard*12", 3),
        ("minecraft:ender_pearl*4", 2), ("minecraft:gold_ingot*8", 3),
    ], "minecraft:chest", crate=("Spark Crate", "#7FD3FF"))
    T("path", "Pathfinder Crate", 2, [
        ("ars_nouveau:source_gem*32", 3), ("irons_spellbooks:uncommon_ink*4", 2),
        ("naturesaura:gold_leaf*8", 2), ("enchanted:mutandis*8", 2),
        ("theurgy:mercury_shard*8", 2), ("minecraft:diamond*4", 3),
        ("minecraft:ender_pearl*8", 3), ("minecraft:blaze_rod*6", 2),
    ], "minecraft:chest", crate=("Pathfinder Crate", "#B57CFF"))
    T("ascendant", "Ascendant Crate", 3, [
        ("apotheosis:sigil_of_socketing*2", 2), ("apotheosis:gem_dust*16", 3),
        ("relics:relic_experience_bottle*4", 2), ("aether:ambrosium_shard*16", 2),
        ("aether:zanite_gemstone*8", 2), ("minecraft:diamond*8", 3),
        ("minecraft:netherite_scrap*2", 2), ("irons_spellbooks:rare_ink*2", 2),
    ], "minecraft:chest", crate=("Ascendant Crate", "#FFD24A"))
    T("cataclysm", "Cataclysm Crate", 4, [
        ("minecraft:netherite_ingot*2", 3), ("irons_spellbooks:epic_ink*2", 2),
        ("cataclysm:ancient_metal_ingot*4", 2), ("minecraft:enchanted_golden_apple", 2),
        ("apotheosis:sigil_of_enhancement*2", 2), ("relics:relic_experience_bottle*8", 2),
    ], "minecraft:chest", crate=("Cataclysm Crate", "#FF4A4A"))

    # Side chapter tables.
    T("guild", "Guild Deco Bundle", 0, [
        ("minecraft:sea_lantern*16", 1), ("minecraft:end_rod*16", 1), ("minecraft:amethyst_block*16", 1),
        ("minecraft:crying_obsidian*16", 1), ("minecraft:prismarine_bricks*32", 1),
        ("minecraft:mud_bricks*64", 1), ("minecraft:calcite*64", 1), ("minecraft:tuff_bricks*64", 1),
        ("minecraft:cherry_planks*64", 1), ("minecraft:ochre_froglight*8", 1),
        ("minecraft:verdant_froglight*8", 1), ("minecraft:pearlescent_froglight*8", 1),
    ], "minecraft:amethyst_block")
    T("guild_tools", "Builder's Tool", 0, [
        ("buildinggadgets2:gadget_building", 1), ("buildinggadgets2:gadget_exchanging", 1),
        ("buildinggadgets2:gadget_copy_paste", 1), ("chiselsandbits:chisel_diamond", 1),
        ("effortlessbuilding:randomizer_tool", 1), ("framedblocks:framed_hammer", 1),
    ], "buildinggadgets2:gadget_building")
    T("tinker", "Tinker's Box", 0, [
        ("computercraft:disk*4", 1), ("minecraft:redstone*32", 1), ("minecraft:gold_ingot*8", 1),
        ("computercraft:cable*16", 1), ("computercraft:wired_modem*4", 1),
    ], "computercraft:computer_normal")
    T("explorer", "Explorer's Pack", 0, [
        ("minecraft:map*4", 1), ("minecraft:spyglass", 1), ("minecraft:golden_carrot*16", 1),
        ("waystones:warp_scroll*3", 1), ("waystones:return_scroll*3", 1),
    ], "minecraft:filled_map")
    T("hunter", "Hunter's Spoils", 0, [
        ("minecraft:golden_apple*2", 1), ("minecraft:arrow*64", 1), ("minecraft:cooked_porkchop*16", 1),
        ("minecraft:iron_ingot*12", 1),
    ], "minecraft:iron_sword")
    T("hearth", "Hearth Basket", 0, [
        ("farmersdelight:beef_stew*4", 1), ("farmersdelight:chicken_soup*4", 1),
        ("farmersdelight:fish_stew*4", 1), ("farmersdelight:baked_cod_stew*4", 1),
        ("farmersdelight:pumpkin_soup*4", 1), ("farmersdelight:honey_glazed_ham_block", 1),
    ], "farmersdelight:cooking_pot")

    # Choice tables. Each offers a taste of a path the team may not have
    # started, but only from items that path makes at that act.
    T("sampler", "A Taste of Each Path", 1, [
        ("ars_nouveau:imbuement_chamber", 1), ("occultism:golden_sacrificial_bowl", 1),
        ("naturesaura:nature_altar", 1),
    ], "minecraft:nether_star")
    T("cross_arcane", "Arcane Path: A Gift Outward", 2, [
        ("malum:spirit_altar", 1), ("naturesaura:gold_powder*16", 1),
    ], "ars_nouveau:source_gem")
    T("cross_occult", "Occult Path: A Gift Outward", 2, [
        ("ars_nouveau:source_gem*32", 1), ("naturesaura:gold_powder*16", 1),
    ], "malum:spirit_altar")
    T("cross_natural", "Natural Path: A Gift Outward", 2, [
        ("ars_nouveau:source_gem*32", 1), ("malum:spirit_altar", 1),
    ], "naturesaura:gold_powder")


# ------------------------------------------------------------ chapters ----

PREV = object()


class Quest:
    def __init__(self, ch, slug, title, tasks, plain, deps, icon, rewards, shape, size, any_dep, optional):
        self.ch, self.slug, self.title, self.tasks, self.plain = ch, slug, title, tasks, plain
        self.deps, self.icon, self.rewards = deps, icon, list(rewards)
        self.shape, self.size, self.any_dep, self.optional = shape, size, any_dep, optional
        self.id = hid(f"quest:{slug}")


class Chapter:
    all = []

    def __init__(self, slug, title, group, icon, act, crate=None, plain=""):
        self.slug, self.title, self.group, self.icon, self.act = slug, title, group, icon, act
        self.crate, self.plain = crate, plain
        self.id = hid(f"chapter:{slug}")
        self.quests = []
        self.row = 0
        self.branch_rows = {}
        Chapter.all.append(self)

    def branch(self, row):
        """Lay the following quests out on a new row."""
        self.row = row
        return self

    def q(self, slug, title, tasks, plain, deps=PREV, icon=None, rewards=(), shape=None,
          size=None, any_dep=False, boss=False, optional=False):
        if deps is PREV:
            deps = [self.quests[-1].slug] if self.quests else []
        elif isinstance(deps, str):
            deps = [deps]
        rewards = list(rewards)
        if boss:
            shape, size = shape or "gear", size or 1.5
            if self.crate:
                rewards.append(f"team:loot:{self.crate}")
        quest = Quest(self, slug, title, tasks if isinstance(tasks, list) else [tasks], plain,
                      list(deps), icon, rewards, shape, size, any_dep, optional)
        quest.row = self.row
        self.quests.append(quest)
        return quest


def task_snbt(qslug, i, spec):
    tid = hid(f"task:{qslug}:{i}")
    kind, _, arg = spec.partition(":")
    if kind == "i":
        iid, n = item(arg)
        t = {"id": tid, "item": {"count": 1, "id": iid}, "type": "item"}
        if n > 1:
            t["count"] = L(n)
        return t
    if kind == "k":
        eid, n = item(arg)
        return {"entity": eid, "id": tid, "type": "kill", "value": L(n)}
    if kind == "d":
        return {"dimension": arg, "id": tid, "type": "dimension"}
    if kind == "a":
        return {"advancement": arg, "criterion": "", "id": tid, "type": "advancement"}
    if kind == "c":
        return {"id": tid, "type": "checkmark"}
    raise ValueError(f"{qslug}: unknown task spec {spec!r}")


def title_tag(name):
    """A name tag that carries a title, as a trophy reward."""
    return ("tag", name)


def reward_snbt(quest, i, spec, act):
    rid = hid(f"reward:{quest.slug}:{i}")
    team = False
    if isinstance(spec, tuple) and spec[0] == "tag":
        r = {"id": rid, "item": {"components": {"minecraft:custom_name": json.dumps(spec[1])},
                                 "count": 1, "id": "minecraft:name_tag"}, "type": "item"}
        return r, None
    if spec.startswith("team:"):
        team, spec = True, spec[5:]
    kind, _, arg = spec.partition(":")
    if kind in ("loot", "choice", "random"):
        table = Table.all.get(arg)
        if table is None:
            raise ValueError(f"{quest.slug}: unknown reward table {arg!r}")
        table_act = table.act
        chapter_act = 0 if act == "side" else act
        if table_act > chapter_act:
            raise ValueError(f"{quest.slug}: table {arg} is act {table_act}, chapter is act {chapter_act}")
        r = {"id": rid, "table_id": L(int(table.id, 16)), "type": kind}
    elif kind == "item":
        iid, n = item(arg)
        r = {"id": rid, "item": {"count": n, "id": iid}, "type": "item"}
    else:
        raise ValueError(f"{quest.slug}: unknown reward spec {spec!r}")
    if team:
        r["team_reward"] = True
    return r, None


SPACING = 1.5


def layout(ch):
    by_slug = {q.slug: q for q in ch.quests}
    depth = {}

    def d(q, stack=()):
        if q.slug in stack:
            raise ValueError(f"dependency cycle through {q.slug}")
        if q.slug not in depth:
            inside = [by_slug[s] for s in q.deps if s in by_slug]
            depth[q.slug] = 1 + max((d(p, stack + (q.slug,)) for p in inside), default=-1)
        return depth[q.slug]

    taken = set()
    for q in ch.quests:
        x = d(q)
        y = q.row * 2
        # Nearest free cell on this column, then further right.
        cell = next(((x + dx, y + off) for dx in range(6) for off in (0, 1, -1, 2, -2, 3, -3)
                     if (x + dx, y + off) not in taken), None)
        if cell is None:
            raise ValueError(f"{ch.slug}: no free cell for {q.slug}")
        x, y = cell
        taken.add((x, y))
        q.x, q.y = x * SPACING, y * SPACING / 2


# --------------------------------------------------------------- build ----


def load_lore():
    return json.loads((HERE / "lore.json").read_text(encoding="utf-8"))


def check_no_cycles(quests_by_slug):
    """Reject dependency cycles across the whole book; layout() only sees one chapter."""
    done, visiting = set(), set()

    def visit(slug):
        if slug in done:
            return
        if slug in visiting:
            raise ValueError(f"dependency cycle through {slug}")
        visiting.add(slug)
        for dep in quests_by_slug[slug].deps:
            visit(dep)
        visiting.discard(slug)
        done.add(slug)

    for slug in quests_by_slug:
        visit(slug)


def build(out):
    lore = load_lore()
    quests_by_slug = {}
    for ch in Chapter.all:
        for q in ch.quests:
            if q.slug in quests_by_slug:
                raise ValueError(f"duplicate quest slug {q.slug}")
            quests_by_slug[q.slug] = q
    for q in quests_by_slug.values():
        for dep in q.deps:
            if dep not in quests_by_slug:
                raise ValueError(f"{q.slug}: unknown dependency {dep}")
    check_no_cycles(quests_by_slug)

    missing = [q.slug for q in quests_by_slug.values() if not lore.get(q.slug)]
    if missing:
        raise ValueError(f"lore.json has no line for: {', '.join(missing)}")

    root = Path(out) / "config" / "ftbquests" / "quests"
    (root / "chapters").mkdir(parents=True, exist_ok=True)
    (root / "reward_tables").mkdir(parents=True, exist_ok=True)
    (root / "lang").mkdir(parents=True, exist_ok=True)

    lang = {"file.0000000000000001.title": "&dArchmage Veyla's Guide"}

    groups = {}
    for ch in Chapter.all:
        if ch.group and ch.group not in groups:
            groups[ch.group] = hid(f"group:{ch.group}")
    group_list = [{"id": gid} for gid in groups.values()]
    for name, gid in groups.items():
        lang[f"chapter_group.{gid}.title"] = name

    (root / "data.snbt").write_text(snbt({
        "default_autoclaim_rewards": "disabled",
        "default_consume_items": False,
        "default_quest_disable_jei": False,
        "default_quest_shape": "circle",
        "default_reward_team": False,
        "detection_delay": 20,
        "disable_gui": False,
        "drop_loot_crates": False,
        "grid_scale": D(0.5),
        "lock_message": "",
        "pause_game": False,
        "progression_mode": "flexible",
        "show_lock_icons": True,
        "version": 13,
    }) + "\n", encoding="utf-8")
    (root / "chapter_groups.snbt").write_text(snbt({"chapter_groups": group_list}) + "\n", encoding="utf-8")

    for order, table in enumerate(Table.all.values()):
        (root / "reward_tables" / f"{table.slug}.snbt").write_text(snbt(table.snbt(order)) + "\n", encoding="utf-8")
        lang[f"reward_table.{table.id}.title"] = table.title

    for order, ch in enumerate(Chapter.all):
        layout(ch)
        lang[f"chapter.{ch.id}.title"] = ch.title
        if ch.plain:
            lang[f"chapter.{ch.id}.chapter_subtitle"] = [ch.plain]
        qs = []
        for q in ch.quests:
            first_task = q.tasks[0]
            icon = q.icon
            if icon is None and first_task[0] in "i" and first_task[1] == ":":
                icon = item(first_task[2:])[0]
            d = {
                "dependencies": [quests_by_slug[s].id for s in q.deps],
                "id": q.id,
                "rewards": [],
                "tasks": [task_snbt(q.slug, i, t) for i, t in enumerate(q.tasks)],
                "x": D(q.x),
                "y": D(q.y),
            }
            if icon:
                d["icon"] = {"id": icon}
            if q.shape:
                d["shape"] = q.shape
            if q.size:
                d["size"] = D(q.size)
            if q.any_dep:
                d["dependency_requirement"] = "one_completed"
            if q.optional:
                d["optional"] = True
            xp = ACT_XP[ch.act]
            d["rewards"].append({"id": hid(f"reward:{q.slug}:xp"), "type": "xp", "xp": xp})
            for i, spec in enumerate(q.rewards):
                r, _ = reward_snbt(q, i, spec, ch.act)
                d["rewards"].append(r)
            qs.append(d)
            lang[f"quest.{q.id}.title"] = q.title
            lang[f"quest.{q.id}.quest_desc"] = ["&d&o" + lore[q.slug], "", q.plain]
        chapter = {
            "default_hide_dependency_lines": False,
            "default_quest_shape": "",
            "filename": ch.slug,
            "group": groups.get(ch.group, ""),
            "icon": {"id": ch.icon},
            "id": ch.id,
            "order_index": order,
            "quest_links": [],
            "quests": qs,
        }
        (root / "chapters" / f"{ch.slug}.snbt").write_text(snbt(chapter) + "\n", encoding="utf-8")

    (root / "lang" / "en_us.snbt").write_text(snbt(lang) + "\n", encoding="utf-8")
    total = sum(len(c.quests) for c in Chapter.all)
    print(f"[quests] {len(Chapter.all)} chapters, {total} quests, {len(Table.all)} reward tables -> {root}")


def dump_outline():
    for ch in Chapter.all:
        print(f"## {ch.slug} | {ch.title}")
        for q in ch.quests:
            print(f"{q.slug}|{q.title}|{q.plain}")


# ------------------------------------------------------------- content ----

MAIN = "The Path"
SIDE = "Side Chapters"
GUILD = "Builder's Guild"


def prologue():
    c = Chapter("prologue", "Prologue: Settling In", MAIN, "minecraft:campfire", 0, crate="hearthstone",
                plain="Find your feet before the magic starts.")
    c.q("welcome", "Welcome, Apprentice", "c", "Tick the box to begin. Quests unlock left to right.",
        icon="ftbquests:book", shape="hexagon", size=1.5, rewards=["item:minecraft:bread*8"])
    c.q("crafting_table", "A Place to Work", "i:minecraft:crafting_table", "Craft a crafting table.")
    c.q("iron_tools", "Iron in Hand", "a:minecraft:story/iron_tools", "Craft an iron pickaxe.",
        icon="minecraft:iron_pickaxe", rewards=["loot:hearthstone"])
    c.q("sleep", "Rest Well", "a:minecraft:adventure/sleep_in_bed", "Sleep in a bed to set your spawn.",
        icon="minecraft:red_bed")
    c.branch(1)
    c.q("flint_knife", "A Cook's Knife", "i:farmersdelight:flint_knife", "Craft a Farmer's Delight knife.",
        deps="crafting_table")
    c.q("cutting_board", "The Cutting Board", "i:farmersdelight:cutting_board",
        "Craft a cutting board. Use your knife on items placed on it.")
    c.q("cooking_pot", "The Cooking Pot", "i:farmersdelight:cooking_pot",
        "Craft a cooking pot and place it over a fire or heat source.")
    c.q("vegetable_soup", "Something Warm", "i:farmersdelight:vegetable_soup", "Cook a bowl of vegetable soup.",
        rewards=["item:farmersdelight:straw*16"])
    c.branch(-1)
    c.q("warp_stone", "A Stone That Remembers", "i:waystones:warp_stone",
        "Craft a warp stone. It takes you to any waystone you have found.", deps="iron_tools")
    c.q("waystone", "Waystone", "i:waystones:waystone", "Craft or find a waystone and activate it.",
        rewards=["item:waystones:warp_scroll*2"])
    c.branch(-2)
    c.q("team", "Gather Your Coven", "c",
        "Open the FTB Teams screen (the team button in your inventory) and make or join a team. "
        "Quest progress is shared per team.", deps="welcome", icon="minecraft:white_banner")
    c.q("claim", "Stake Your Claim", "c",
        "Open the map (M) and claim the chunks around your base. Claimed land is safe from griefing and "
        "explosions.", icon="minecraft:filled_map")
    c.q("minimap", "Read the Map", "c",
        "Your minimap is in the corner. Press M for the full map, and add a waypoint at home.",
        icon="minecraft:compass")
    c.q("corpse", "Death Is Not the End", "c",
        "When you die, your items stay in a corpse where you fell. Walk back and open it to get them.",
        icon="minecraft:skeleton_skull")
    c.branch(2)
    c.q("hostility_detector", "Sense the Danger", "i:l2hostility:hostility_detector",
        "Craft a Hostility Detector. It shows how dangerous the mobs in this chunk are.", deps="iron_tools")
    c.q("hostility_orb", "Calm the Town", "i:l2hostility:hostility_orb",
        "Craft a Hostility Orb. Use it to clear the difficulty in the chunks around your town.",
        rewards=["loot:hearthstone"])
    c.branch(3)
    c.q("vr_tips", "Seeing in Two Worlds", "c",
        "Playing in VR? Start SteamVR before the game. ImmersiveMC lets you use crafting tables, furnaces "
        "and anvils with your hands. Not in VR? Tick this anyway.", deps="welcome", icon="minecraft:ender_eye")
    c.q("immersive_craft", "Craft With Your Hands", "c",
        "In VR, reach into a crafting table and place items by hand. On desktop, tick this box.",
        icon="minecraft:crafting_table")
    c.branch(-3)
    c.q("backpack", "Carry More", "i:sophisticatedbackpacks:backpack", "Craft a backpack.", deps="crafting_table")
    c.branch(4)
    c.q("door", "A Proper Door", "i:mcwdoors:oak_cottage_door", "Craft an oak cottage door.", deps="crafting_table")
    c.q("windows", "Light Through Glass", "i:mcwwindows:oak_four_window*4", "Craft four oak windows.")
    c.q("hearth_home", "Hearth and Home", "c",
        "Build a house with a door and windows from this chapter. Tick the box when it feels like home.",
        icon="minecraft:campfire", shape="hexagon", size=1.5, optional=True,
        rewards=["team:loot:hearthstone", "team:loot:guild"])
    c.branch(0)
    c.q("ready", "Ready for Magic", "c",
        "Tick the box when you are ready. Act I opens.",
        deps=["sleep", "vegetable_soup", "waystone", "hostility_detector"], icon="minecraft:enchanted_book",
        shape="hexagon", size=1.5, rewards=["loot:hearthstone"])


def act1():
    c = Chapter("act1", "Act I: First Sparks", MAIN, "ars_nouveau:novice_spell_book", 1, crate="spark",
                plain="Touch each school of magic once, then face the Twilight Forest.")
    c.q("act1_start", "The First Spark", "c", "Four schools of magic wait for you. Try each one.",
        deps="ready", icon="minecraft:amethyst_shard", shape="hexagon", size=1.5)
    # Ars Nouveau
    c.branch(-3)
    c.q("worn_notebook", "A Worn Notebook", "i:ars_nouveau:worn_notebook",
        "Craft the Ars Nouveau guide, the Worn Notebook.")
    c.q("novice_book", "Novice Spell Book", "a:ars_nouveau:novice_spell_book",
        "Craft a Novice Spell Book.", icon="ars_nouveau:novice_spell_book", rewards=["loot:spark"])
    c.q("scribes_table", "The Scribe's Table", "i:ars_nouveau:scribes_table",
        "Craft a Scribe's Table. Use it to learn new glyphs.")
    c.q("source_gem", "Source", "i:ars_nouveau:source_gem*4",
        "Make source gems in an Imbuement Chamber, or find them in the world.")
    c.q("imbuement_chamber", "The Imbuement Chamber", "i:ars_nouveau:imbuement_chamber",
        "Craft an Imbuement Chamber.", deps="scribes_table")
    c.q("source_jar", "Bottled Source", "i:ars_nouveau:source_jar", "Craft a Source Jar.", deps="source_gem")
    c.q("sourcelink", "Living Source", "i:ars_nouveau:agronomic_sourcelink",
        "Craft an Agronomic Sourcelink. Growing crops near it makes source.")
    # Hexerei
    c.branch(-1)
    c.q("mixing_cauldron", "The Mixing Cauldron", "i:hexerei:mixing_cauldron",
        "Craft a Hexerei Mixing Cauldron.", deps="act1_start")
    c.q("drying_rack", "Herbs to Dry", "i:hexerei:herb_drying_rack", "Craft a Herb Drying Rack.")
    c.q("pestle", "Grind and Crush", "i:hexerei:pestle_and_mortar", "Craft a Pestle and Mortar.")
    c.q("broom_brush", "A Broom's Bristles", "i:hexerei:broom_brush", "Craft a broom brush.")
    c.q("willow_broom", "Take to the Sky", "i:hexerei:willow_broom", "Craft a willow broom and fly.",
        rewards=["loot:spark"])
    # Eidolon
    c.branch(1)
    c.q("codex", "The Codex", "i:eidolon_repraised:codex", "Craft Eidolon's Codex.", deps="act1_start")
    c.q("worktable", "The Worktable", "i:eidolon_repraised:worktable", "Craft an Eidolon Worktable.")
    c.q("research_table", "Research", "i:eidolon_repraised:research_table", "Craft a Research Table.")
    c.q("athame", "The Athame", "i:eidolon_repraised:athame", "Craft an Athame.", deps="worktable")
    c.q("soul_shard", "A Fragment of Soul", "i:eidolon_repraised:soul_shard",
        "Collect a soul shard by slaying undead.", rewards=["loot:spark"])
    # Iron's Spells
    c.branch(3)
    c.q("inscription_table", "The Inscription Table", "i:irons_spellbooks:inscription_table",
        "Craft an Inscription Table.", deps="act1_start")
    c.q("arcane_essence", "Arcane Essence", "i:irons_spellbooks:arcane_essence*8",
        "Gather arcane essence from mobs or by breaking down scrolls.")
    c.q("first_scroll", "Your First Scroll", "a:irons_spellbooks:irons_spellbooks/root",
        "Find or craft any Iron's Spells scroll.", icon="irons_spellbooks:scroll")
    c.q("copper_spell_book", "A Copper Spell Book", "i:irons_spellbooks:copper_spell_book",
        "Craft a copper spell book and inscribe a spell into it.", rewards=["loot:spark"])
    # The gate
    c.branch(0)
    c.q("tf_portal", "Into the Twilight", "d:twilightforest:twilight_forest",
        "Throw a diamond into a ring of flowers around water to open a Twilight Forest portal. Step through.",
        deps=["novice_book", "willow_broom", "soul_shard", "first_scroll"], icon="twilightforest:twilight_portal_miniature_structure")
    c.q("naga", "The Naga", "k:twilightforest:naga", "Slay the Naga in its courtyard.",
        icon="twilightforest:naga_trophy", boss=True)
    c.q("lich", "The Lich", "k:twilightforest:lich", "Slay the Lich at the top of its tower.",
        icon="twilightforest:lich_trophy", boss=True)
    c.q("act1_end", "Three Paths Open", "c",
        "Tick the box. The three paths of Act II open. Your team can follow any of them.",
        icon="minecraft:nether_star", shape="hexagon", size=2.0, rewards=["choice:sampler"])
    for q in c.quests:
        if q.slug == "tf_portal":
            q.icon = "minecraft:diamond"


def path_chapter(slug, title, icon, plain):
    return Chapter(slug, title, MAIN, icon, 2, crate="path", plain=plain)


def cross(c, path, a_spec, a_title, b_spec, b_title, deps):
    """Two item quests (one from each other path) and a hub that needs either."""
    c.q(f"{path}_cross_a", a_title, f"i:{a_spec}", "Bring one of these from another path. Either quest is enough.",
        deps=deps)
    c.q(f"{path}_cross_b", b_title, f"i:{b_spec}", "Bring one of these from another path. Either quest is enough.",
        deps=deps)
    c.q(f"{path}_cross", "A Bridge Between Paths", "c",
        "Finish either of the two quests before this one. Then tick the box.",
        deps=[f"{path}_cross_a", f"{path}_cross_b"], any_dep=True, icon="minecraft:chain", shape="diamond")


CROSS = {
    "arcane": "ars_nouveau:enchanting_apparatus",
    "occult": "malum:soul_stained_steel_ingot*4",
    "natural": "naturesaura:infused_iron*4",
}


def arcane():
    c = path_chapter("arcane", "Act II: The Arcane Path", "ars_nouveau:apprentice_spell_book",
                     "Ars Nouveau, Ars Elemental, Iron's Spells and Mahou Tsukai.")
    c.q("arcane_start", "The Arcane Path", "c", "Tick the box to walk the Arcane Path.", deps="act1_end",
        icon="ars_nouveau:source_gem", shape="hexagon", size=1.5)
    c.branch(-3)
    c.q("apprentice_book", "Apprentice Spell Book", "a:ars_nouveau:apprentice_spell_book",
        "Upgrade to an Apprentice Spell Book.", icon="ars_nouveau:apprentice_spell_book")
    c.q("arcane_core", "Arcane Core", "i:ars_nouveau:arcane_core", "Craft an Arcane Core.")
    c.q("arcane_pedestal", "Pedestals", "i:ars_nouveau:arcane_pedestal*4", "Craft four Arcane Pedestals.")
    c.q("enchanting_apparatus", "The Enchanting Apparatus", "i:ars_nouveau:enchanting_apparatus",
        "Craft an Enchanting Apparatus.", rewards=["choice:cross_arcane"])
    c.q("ritual_brazier", "The Ritual Brazier", "i:ars_nouveau:ritual_brazier", "Craft a Ritual Brazier.")
    c.q("wilden_parts", "Trophies of the Wilden", ["i:ars_nouveau:wilden_horn", "i:ars_nouveau:wilden_spike",
                                                   "i:ars_nouveau:wilden_wing"],
        "Collect a horn, a spike and a wing from the Wilden.", icon="ars_nouveau:wilden_horn")
    c.q("wilden_summon", "Call the Chimera", "i:ars_nouveau:ritual_wilden_summon",
        "Craft the Ritual of Summon Wilden. With it, you can call the Wilden Chimera.")
    c.q("wilden_chimera", "The Wilden Chimera", "k:ars_nouveau:wilden_boss", "Slay the Wilden Chimera.",
        icon="ars_nouveau:wilden_tribute", boss=True)
    c.q("archmage_book", "Archmage Spell Book", "a:ars_nouveau:archmage_spell_book",
        "Upgrade to an Archmage Spell Book.", icon="ars_nouveau:archmage_spell_book", rewards=["loot:path"])
    c.branch(-4)
    c.q("starbuncle", "A Little Helper", "i:ars_nouveau:starbuncle_charm",
        "Get a Starbuncle charm. Starbuncles carry items between chests.", deps="arcane_core")
    c.q("wixie", "The Wixie", "i:ars_nouveau:wixie_charm", "Get a Wixie charm. Wixies craft for you.")
    c.q("turret", "Spell Turret", "i:ars_nouveau:basic_spell_turret", "Craft a Basic Spell Turret.")
    c.q("relay", "Source Relay", "i:ars_nouveau:relay", "Craft a Source Relay to move source around.")
    c.branch(-2)
    c.q("fire_focus", "A Focus of Flame", "i:ars_elemental:lesser_fire_focus",
        "Craft a Lesser Fire Focus from Ars Elemental.", deps="enchanting_apparatus")
    c.q("bangle", "The Bangle", "i:ars_elemental:base_bangle", "Craft a Bangle.")
    c.q("curio_bag", "A Bag for Charms", "i:ars_elemental:curio_bag", "Craft a Curio Bag.")
    c.q("mark_of_mastery", "Mark of Mastery", "a:ars_nouveau:mark_of_mastery",
        "Earn the Mark of Mastery.", icon="ars_nouveau:archmage_spell_book")
    # Iron's
    c.branch(0)
    c.q("arcane_anvil", "The Arcane Anvil", "i:irons_spellbooks:arcane_anvil", "Craft an Arcane Anvil.",
        deps="arcane_start")
    c.q("scroll_forge", "The Scroll Forge", "i:irons_spellbooks:scroll_forge", "Craft a Scroll Forge.")
    c.q("uncommon_ink", "Better Ink", "i:irons_spellbooks:uncommon_ink*2", "Brew two bottles of uncommon ink.")
    c.q("blank_rune", "A Blank Rune", "i:irons_spellbooks:blank_rune", "Craft a blank rune.")
    c.q("arcane_ingot", "Arcane Ingot", "i:irons_spellbooks:arcane_ingot*2", "Craft two arcane ingots.")
    c.q("mithril", "Mithril", "i:irons_spellbooks:mithril_ingot", "Find mithril deep underground and smelt it.")
    c.q("iron_spell_book", "An Iron Spell Book", "i:irons_spellbooks:iron_spell_book",
        "Craft an iron spell book.", deps="arcane_ingot")
    c.q("upgrade_orb", "Upgrade Orb", "i:irons_spellbooks:upgrade_orb",
        "Craft an upgrade orb to improve armour.", deps="arcane_ingot")
    c.q("catacombs", "Into the Catacombs", "a:irons_spellbooks:irons_spellbooks/enter_catacombs",
        "Find and enter the Catacombs.", deps="iron_spell_book", icon="minecraft:skeleton_skull")
    c.q("dead_king", "The Dead King", "k:irons_spellbooks:dead_king",
        "Slay the Dead King in the depths of the Catacombs.", icon="irons_spellbooks:dead_king_phylactery",
        boss=True)
    # Mahou Tsukai
    c.branch(2)
    c.q("mahou_guide", "Mahou Tsukai", "i:mahoutsukai:guidebook", "Get the Mahou Tsukai guidebook.",
        deps="arcane_start")
    c.q("mahou_mortar", "Mortar and Pestle", "i:mahoutsukai:mortar_and_pestle", "Craft a Mortar and Pestle.")
    c.q("powdered_diamond", "Diamond Dust", "i:mahoutsukai:powdered_diamond", "Grind a diamond into powder.")
    c.q("attuned_diamond", "An Attuned Diamond", "i:mahoutsukai:attuned_diamond", "Make an Attuned Diamond.")
    c.q("mahoujin", "Draw the Circle", "i:mahoutsukai:mahoujin", "Craft a magic circle (mahoujin).")
    c.q("projection", "Projection", "i:mahoutsukai:scroll_projection",
        "Make a Projection scroll and learn the magecraft.")
    c.q("strengthening", "Reinforcement", "i:mahoutsukai:scroll_strengthening",
        "Make a Reinforcement scroll.", deps="mahoujin")
    # The bridge and the final
    c.branch(5)
    cross(c, "arcane", CROSS["occult"], "Borrowed from the Occult", CROSS["natural"], "Borrowed from Nature",
          deps="arcane_start")
    c.branch(0)
    c.q("arcane_final", "Master of the Arcane", "c",
        "The Arcane Path is done. Act III opens for your team.",
        deps=["archmage_book", "dead_king", "projection", "mark_of_mastery", "arcane_cross"],
        icon="ars_nouveau:archmage_spell_book", shape="hexagon", size=2.0, rewards=["team:loot:path"])


def occult():
    c = path_chapter("occult", "Act II: The Occult Path", "occultism:golden_sacrificial_bowl",
                     "Occultism, Malum, Goety and Eidolon.")
    c.q("occult_start", "The Occult Path", "c", "Tick the box to walk the Occult Path.", deps="act1_end",
        icon="occultism:spirit_attuned_gem", shape="hexagon", size=1.5)
    # Occultism
    c.branch(-3)
    c.q("sacrificial_bowl", "The Sacrificial Bowl", "i:occultism:sacrificial_bowl",
        "Craft a Sacrificial Bowl.")
    c.q("white_chalk", "White Chalk", "i:occultism:chalk_white", "Craft white chalk to draw pentacles.")
    c.q("golden_bowl", "The Golden Bowl", "i:occultism:golden_sacrificial_bowl",
        "Craft a Golden Sacrificial Bowl. It sits at the centre of a ritual.")
    c.q("attuned_gem", "Spirit-Attuned Gem", "i:occultism:spirit_attuned_gem", "Make a Spirit Attuned Gem.")
    c.q("foliot_book", "Bind a Foliot", "i:occultism:book_of_binding_foliot",
        "Craft a Book of Binding for a Foliot.")
    c.q("bound_foliot", "A Name Bound", "i:occultism:book_of_binding_bound_foliot",
        "Bind the Foliot's name into the book.")
    c.q("lumberjack", "A Servant of Wood", "i:occultism:book_of_calling_foliot_lumberjack",
        "Craft a Book of Calling for a Foliot lumberjack.")
    c.q("iesnium", "Iesnium", "i:occultism:iesnium_ingot", "Smelt an iesnium ingot.", deps="attuned_gem")
    c.q("storage_controller", "Dimensional Storage", "i:occultism:storage_controller",
        "Craft an Occultism Storage Controller.")
    c.q("afrit", "The Unbound Afrit", "k:occultism:afrit_wild",
        "Summon and slay a wild Afrit.", deps="bound_foliot", icon="occultism:afrit_essence", boss=True)
    c.q("afrit_essence", "Essence of Fire", "i:occultism:afrit_essence", "Collect Afrit essence.")
    # Malum
    c.branch(-1)
    c.q("encyclopedia", "Encyclopedia Arcana", "i:malum:encyclopedia_arcana",
        "Craft Malum's Encyclopedia Arcana.", deps="occult_start")
    c.q("crude_scythe", "A Crude Scythe", "i:malum:crude_scythe",
        "Craft a crude scythe. Kills with it free spirits.")
    c.q("soulstone", "Raw Soulstone", "i:malum:raw_soulstone*4", "Mine four raw soulstone.")
    c.q("spirit_altar", "The Spirit Altar", "i:malum:spirit_altar", "Craft a Spirit Altar.",
        deps=["crude_scythe", "soulstone"])
    c.q("soul_stained_steel", "Soul-Stained Steel", "i:malum:soul_stained_steel_ingot*4",
        "Infuse four soul-stained steel ingots.", rewards=["choice:cross_occult"])
    c.q("hallowed_gold", "Hallowed Gold", "i:malum:hallowed_gold_ingot*4", "Infuse four hallowed gold ingots.",
        deps="spirit_altar")
    c.q("spirit_jar", "A Jar for Spirits", "i:malum:spirit_jar", "Craft a spirit jar.")
    c.q("spirit_crucible", "The Spirit Crucible", "i:malum:spirit_crucible", "Craft a Spirit Crucible.",
        deps="soul_stained_steel")
    c.q("totem_base", "Runewood Totem", "i:malum:runewood_totem_base", "Craft a Runewood Totem Base.",
        deps="spirit_altar")
    c.q("gilded_ring", "A Gilded Ring", "i:malum:gilded_ring", "Craft a Gilded Ring.", deps="hallowed_gold")
    # Goety
    c.branch(1)
    c.q("dark_wand", "The Dark Wand", "i:goety:dark_wand", "Craft Goety's Dark Wand.", deps="occult_start")
    c.q("dark_altar", "The Dark Altar", "i:goety:dark_altar", "Craft a Dark Altar.")
    c.q("cursed_ingot", "Cursed Metal", "i:goety:cursed_ingot*4", "Craft four cursed ingots.")
    c.q("cursed_infuser", "The Cursed Infuser", "i:goety:cursed_infuser", "Craft a Cursed Infuser.")
    c.q("dark_robe", "Robes of Shadow", "i:goety:dark_robe", "Craft a dark robe.")
    c.q("blazing_focus", "A Burning Focus", "i:goety:blazing_focus", "Craft a Blazing Focus.",
        deps="cursed_infuser")
    c.q("vizier", "The Vizier", "k:goety:vizier",
        "Slay the Vizier. Raid captains carry the summoning; Goety's guide shows how.", icon="minecraft:totem_of_undying",
        boss=True)
    # Eidolon
    c.branch(3)
    c.q("stone_altar", "A Stone Altar", "a:eidolon_repraised:stone_altar", "Build an Eidolon stone altar.",
        deps="occult_start", icon="eidolon_repraised:stone_altar")
    c.q("crucible", "The Crucible", "i:eidolon_repraised:crucible", "Craft a Crucible.")
    c.q("arcane_gold", "Arcane Gold", "i:eidolon_repraised:arcane_gold_ingot*2", "Brew two arcane gold ingots.")
    c.q("soul_enchanter", "The Soul Enchanter", "i:eidolon_repraised:soul_enchanter",
        "Craft a Soul Enchanter.")
    c.q("lesser_soul_gem", "A Lesser Soul Gem", "i:eidolon_repraised:lesser_soul_gem",
        "Craft a lesser soul gem.", deps="arcane_gold")
    c.q("reaper_scythe", "The Reaper's Scythe", "i:eidolon_repraised:reaper_scythe",
        "Craft a Reaper Scythe.", deps="lesser_soul_gem")
    c.branch(5)
    cross(c, "occult", CROSS["arcane"], "Borrowed from the Arcane", CROSS["natural"], "Borrowed from Nature",
          deps="occult_start")
    c.branch(0)
    c.q("occult_final", "Master of the Occult", "c",
        "The Occult Path is done. Act III opens for your team.",
        deps=["afrit_essence", "vizier", "spirit_crucible", "reaper_scythe", "occult_cross"],
        icon="malum:spirit_altar", shape="hexagon", size=2.0, rewards=["team:loot:path"])


def natural():
    c = path_chapter("natural", "Act II: The Natural Path", "naturesaura:nature_altar",
                     "Nature's Aura, Hexerei, Enchanted: Witchcraft and Theurgy.")
    c.q("natural_start", "The Natural Path", "c", "Tick the box to walk the Natural Path.", deps="act1_end",
        icon="naturesaura:gold_leaf", shape="hexagon", size=1.5)
    # Nature's Aura
    c.branch(-3)
    c.q("na_book", "Book of Natural Aura", "a:naturesaura:get_book", "Get the Nature's Aura book.",
        icon="naturesaura:book")
    c.q("gold_fiber", "Golden Fibre", "i:naturesaura:gold_fiber*4", "Make four gold fibres.")
    c.q("gold_leaf", "Golden Leaves", "i:naturesaura:gold_leaf*4", "Collect four golden leaves.")
    c.q("wood_stand", "Wooden Stands", "i:naturesaura:wood_stand*4", "Craft four Wooden Stands.")
    c.q("nature_altar", "The Natural Altar", "i:naturesaura:nature_altar", "Build a Natural Altar.")
    c.q("infused_iron", "Infused Iron", "i:naturesaura:infused_iron*4", "Infuse four iron ingots at the altar.",
        rewards=["choice:cross_natural"])
    c.q("eye", "The Environmental Eye", "i:naturesaura:eye", "Craft an Environmental Eye to see the aura.",
        deps="nature_altar")
    c.q("flower_generator", "A Garden of Aura", "i:naturesaura:flower_generator",
        "Craft a Flowery Generator. Flowers nearby feed the aura.", deps="infused_iron")
    c.q("offering_table", "The Offering Table", "i:naturesaura:offering_table", "Craft an Offering Table.",
        deps="infused_iron")
    c.q("sky_ingot", "Ingot of the Sky", "i:naturesaura:sky_ingot", "Make a sky ingot at the Offering Table.")
    c.q("conversion_catalyst", "Conversion Catalyst", "i:naturesaura:conversion_catalyst",
        "Craft a Conversion Catalyst.", deps="nature_altar")
    # Hexerei
    c.branch(-1)
    c.q("book_of_shadows", "Book of Shadows", "i:hexerei:book_of_shadows", "Craft a Book of Shadows.",
        deps="natural_start")
    c.q("selenite", "Selenite", "i:hexerei:selenite_shard*4", "Mine four selenite shards.")
    c.q("crystal_ball", "The Crystal Ball", "i:hexerei:crystal_ball", "Craft a Crystal Ball.")
    c.q("crow_ankh", "The Crow's Ankh", "i:hexerei:crow_ankh_amulet", "Craft a Crow Ankh Amulet.",
        deps="selenite")
    c.q("blood_sigil", "A Sigil of Blood", "i:hexerei:blood_sigil", "Craft a Blood Sigil.")
    c.q("sage_bundle", "Burning Sage", "i:hexerei:dried_sage_bundle", "Dry a sage bundle on your rack.",
        deps="natural_start")
    # Enchanted
    c.branch(1)
    c.q("witch_altar", "The Witch's Altar", "i:enchanted:altar", "Build an Enchanted altar.",
        deps="natural_start")
    c.q("witch_oven", "The Witch's Oven", "i:enchanted:witch_oven", "Craft a Witch's Oven.")
    c.q("distillery", "The Distillery", "i:enchanted:distillery", "Craft a Distillery.")
    c.q("kettle", "The Kettle", "i:enchanted:kettle", "Craft a Kettle.", deps="witch_oven")
    c.q("witch_cauldron", "The Witch's Cauldron", "i:enchanted:witch_cauldron", "Craft a Witch's Cauldron.",
        deps="witch_oven")
    c.q("ritual_chalk", "Ritual Chalk", "i:enchanted:ritual_chalk", "Craft ritual chalk.", deps="witch_altar")
    c.q("mutandis", "Mutandis", "i:enchanted:mutandis*4", "Brew four Mutandis.", deps="witch_oven")
    c.q("poppet", "A Poppet", "i:enchanted:poppet", "Craft a poppet.", deps="distillery")
    c.q("enchanted_broom", "The Enchanted Broom", "i:enchanted:enchanted_broomstick",
        "Craft an Enchanted Broomstick.", deps="ritual_chalk")
    c.q("attuned_stone", "A Charged Stone", "i:enchanted:attuned_stone_charged", "Charge an Attuned Stone.",
        deps="ritual_chalk")
    # Theurgy
    c.branch(3)
    c.q("divination_rod", "The Divination Rod", "i:theurgy:divination_rod_t1",
        "Craft a basic divination rod. It finds ores for you.", deps="natural_start")
    c.q("calcination_oven", "Calcination", "i:theurgy:calcination_oven", "Craft a Calcination Oven.")
    c.q("liquefaction", "Liquefaction", "i:theurgy:liquefaction_cauldron", "Craft a Liquefaction Cauldron.")
    c.q("distiller", "The Distiller", "i:theurgy:distiller", "Craft a Theurgy Distiller.")
    c.q("incubator", "The Incubator", "i:theurgy:incubator", "Craft an Incubator.")
    c.q("mercury", "Mercury", "i:theurgy:mercury_shard*8", "Make eight mercury shards.", deps="calcination_oven")
    # The boss. The Natural mods have no boss of their own, so the
    # Twilight Forest's Minoshroom stands in.
    c.branch(5)
    cross(c, "natural", CROSS["arcane"], "Borrowed from the Arcane", CROSS["occult"], "Borrowed from the Occult",
          deps="natural_start")
    c.branch(-5)
    c.q("minoshroom", "The Minoshroom", "k:twilightforest:minoshroom",
        "Find the Labyrinth in the Twilight Forest swamp and slay the Minoshroom.", deps="natural_start",
        icon="twilightforest:minoshroom_trophy", boss=True)
    c.branch(0)
    c.q("natural_final", "Master of the Wild", "c",
        "The Natural Path is done. Act III opens for your team.",
        deps=["sky_ingot", "minoshroom", "enchanted_broom", "mercury", "crystal_ball", "natural_cross"],
        icon="naturesaura:nature_altar", shape="hexagon", size=2.0, rewards=["team:loot:path"])


def act3():
    c = Chapter("act3", "Act III: Ascendant", MAIN, "apotheosis:gem", 3, crate="ascendant",
                plain="Gems, relics, new skies and deep places. Then the Twilight's last gates.")
    c.q("act3_start", "Ascendant", "c", "Finish any one Act II path to open this chapter. Then tick the box.",
        deps=["arcane_final", "occult_final", "natural_final"], any_dep=True, icon="minecraft:nether_star",
        shape="hexagon", size=2.0)
    # Gems and relics
    c.branch(-4)
    c.q("gem_cutting", "The Gem Cutting Table", "i:apotheosis:gem_cutting_table", "Craft a Gem Cutting Table.")
    c.q("gem", "A Gem", "i:apotheosis:gem", "Find any Apotheosis gem.")
    c.q("socketing", "Sockets", "i:apotheosis:sigil_of_socketing", "Get a Sigil of Socketing.")
    c.q("augmenting", "Augmenting", "i:apotheosis:augmenting_table", "Craft an Augmenting Table.",
        deps="gem_cutting")
    c.q("reforging", "Reforging", "i:apotheosis:reforging_table", "Craft a Reforging Table.", deps="gem_cutting")
    c.q("salvaging", "Salvaging", "i:apotheosis:salvaging_table", "Craft a Salvaging Table.", deps="gem_cutting")
    c.q("enhancement", "Enhancement", "i:apotheosis:sigil_of_enhancement", "Get a Sigil of Enhancement.",
        deps="reforging")
    c.branch(-3)
    c.q("hellshelf", "Hellshelves", "i:apothic_enchanting:hellshelf*4",
        "Craft four Hellshelves for stronger enchanting.", deps="act3_start")
    c.q("seashelf", "Seashelves", "i:apothic_enchanting:seashelf*4", "Craft four Seashelves.")
    c.branch(-2)
    c.q("researching_table", "Study the Relics", "i:relics:researching_table",
        "Craft a Researching Table. It reveals what a relic can do.", deps="act3_start")
    c.q("magic_mirror", "The Magic Mirror", "i:relics:magic_mirror", "Find a Magic Mirror relic.")
    c.q("roller_skates", "Roller Skates", "i:relics:roller_skates", "Find a pair of Roller Skates.",
        deps="researching_table")
    c.q("relic_xp", "Relic Experience", "i:relics:relic_experience_bottle",
        "Get a bottle of relic experience.", deps="researching_table")
    # Skyward
    c.branch(0)
    c.q("aether", "Into the Aether", "d:aether:the_aether",
        "Build a glowstone portal and light it with water. Enter the Aether.", deps="act3_start",
        icon="minecraft:glowstone")
    c.q("aether_altar", "The Altar", "a:aether:craft_altar", "Craft an Altar in the Aether.",
        icon="aether:altar")
    c.q("zanite", "Zanite", "a:aether:zanite", "Mine zanite.", icon="aether:zanite_gemstone")
    c.q("slider", "The Slider", "k:aether:slider", "Defeat the Slider in a bronze dungeon.",
        icon="aether:bronze_dungeon_key", boss=True)
    c.q("valkyrie_queen", "The Valkyrie Queen", "k:aether:valkyrie_queen",
        "Defeat the Valkyrie Queen in a silver dungeon.", icon="aether:silver_dungeon_key", boss=True)
    c.q("sun_spirit", "The Sun Spirit", "k:aether:sun_spirit", "Defeat the Sun Spirit in a gold dungeon.",
        icon="aether:gold_dungeon_key", boss=True)
    c.branch(1)
    c.q("deep_aether", "The Deep Aether", "a:deep_aether:explore_aether",
        "Explore the Deep Aether's new biomes.", deps="aether", icon="deep_aether:skyjade")
    c.q("brass_dungeon", "The Brass Dungeon", "a:deep_aether:brass_dungeon", "Find a brass dungeon.",
        icon="minecraft:bell")
    c.q("aether_champion", "Aether Champion", "a:deep_aether:aether_champion",
        "Earn Deep Aether's champion advancement.", icon="minecraft:golden_sword")
    # The depths
    c.branch(2)
    c.q("otherside", "The Otherside", "d:deeperdarker:otherside",
        "Find an Ancient City and open the portal to the Otherside.", deps="act3_start",
        icon="minecraft:sculk")
    c.q("warden", "The Warden", "k:minecraft:warden", "Slay a Warden.", icon="minecraft:sculk_shrieker",
        boss=True)
    c.q("echo_shard", "Reinforced Echo", "i:deeperdarker:reinforced_echo_shard",
        "Craft a reinforced echo shard.")
    c.q("heart_of_deep", "Heart of the Deep", "i:deeperdarker:heart_of_the_deep",
        "Collect a Heart of the Deep.", deps="otherside")
    c.branch(3)
    c.q("cornelia", "Captain Cornelia", "k:aquamirae:captain_cornelia",
        "Slay Captain Cornelia on the frozen seas.", deps="act3_start", icon="minecraft:trident", boss=True)
    c.q("maze_mother", "The Maze Mother", "k:aquamirae:maze_mother", "Slay the Maze Mother.",
        icon="minecraft:prismarine_crystals", boss=True)
    c.branch(4)
    c.q("undergarden", "The Undergarden", "d:undergarden:undergarden",
        "Light a portal of stone bricks with a catalyst. Enter the Undergarden.", deps="act3_start",
        icon="minecraft:stone_bricks")
    c.q("forgotten_guardian", "The Forgotten Guardian", "k:undergarden:forgotten_guardian",
        "Slay a Forgotten Guardian in the Catacombs.", icon="minecraft:iron_block", boss=True)
    # Rising bosses
    c.branch(5)
    for slug, ent, title, plain, icon in [
        ("bfb_pirate", "pirate_captain", "The Pirate Captain", "Slay the Pirate Captain.", "minecraft:spyglass"),
        ("bfb_kraken", "kraken", "The Kraken", "Slay the Kraken.", "minecraft:ink_sac"),
        ("bfb_sandworm", "sandworm", "The Sandworm", "Slay the Sandworm.", "minecraft:sand"),
        ("bfb_yeti", "yeti", "The Yeti", "Slay the Yeti.", "minecraft:snow_block"),
        ("bfb_underworld", "underworld_knight", "The Underworld Knight", "Slay the Underworld Knight.",
         "minecraft:netherite_sword"),
        ("bfb_dragon", "infernal_dragon", "The Infernal Dragon", "Slay the Infernal Dragon.",
         "minecraft:dragon_head"),
    ]:
        c.q(slug, title, f"k:block_factorys_bosses:{ent}", plain + " Bosses'Rise lairs hold it.",
            deps="act3_start" if slug == "bfb_pirate" else PREV, icon=icon, boss=True)
    # The gate
    c.branch(-6)
    c.q("gate_minoshroom", "The Labyrinth", "k:twilightforest:minoshroom",
        "Slay the Minoshroom. The Twilight Forest opens its next lands after it.", deps="act3_start",
        icon="twilightforest:minoshroom_trophy", boss=True)
    c.q("hydra", "The Hydra", "k:twilightforest:hydra", "Slay the Hydra in the fire swamp.",
        icon="twilightforest:hydra_trophy", boss=True)
    c.q("knight_phantom", "The Knight Phantoms", "k:twilightforest:knight_phantom*6",
        "Slay the six Knight Phantoms in the Dark Forest stronghold.", icon="twilightforest:knight_phantom_trophy",
        boss=True)
    c.q("ur_ghast", "The Ur-Ghast", "k:twilightforest:ur_ghast", "Slay the Ur-Ghast in the Dark Tower.",
        icon="twilightforest:ur_ghast_trophy", boss=True)
    c.q("wither", "The Wither", "k:minecraft:wither", "Summon and slay the Wither.",
        icon="minecraft:wither_skeleton_skull", boss=True)
    c.q("act3_end", "The Last Door", "c", "Tick the box. The Cataclysm waits.",
        icon="minecraft:nether_star", shape="hexagon", size=2.0, rewards=["team:loot:ascendant"])


def finale():
    c = Chapter("finale", "Finale: The Cataclysm", MAIN, "cataclysm:music_disc_ignis", 4, crate="cataclysm",
                plain="The greatest foes in this world. Each kill earns a title.")
    c.q("finale_start", "The Cataclysm", "c", "Tick the box. Every boss here gives a title.", deps="act3_end",
        icon="minecraft:nether_star", shape="hexagon", size=2.0)
    c.q("ender_dragon", "The Ender Dragon", "k:minecraft:ender_dragon", "Slay the Ender Dragon.",
        icon="minecraft:dragon_egg", boss=True, rewards=[title_tag("Dragonsbane")])
    bosses = [
        ("ignis", "ignis", "Burning Arena", "cataclysm:music_disc_ignis", "Slayer of Ignis"),
        ("harbinger", "the_harbinger", "Ancient Factory", "cataclysm:music_disc_the_harbinger", "Bane of the Harbinger"),
        ("leviathan", "the_leviathan", "Sunken City", "cataclysm:music_disc_the_leviathan", "Leviathan's End"),
        ("ender_guardian", "ender_guardian", "Ruined Citadel", "cataclysm:music_disc_ender_guardian",
         "Breaker of the Guardian"),
        ("monstrosity", "netherite_monstrosity", "Soul Black Smith", "cataclysm:music_disc_netherite_monstrosity",
         "Monster Hunter"),
        ("maledictus", "maledictus", "Frosted Prison", "cataclysm:music_disc_maledictus", "Curse Breaker"),
        ("ancient_remnant", "ancient_remnant", "Cursed Pyramid", "cataclysm:music_disc_ancient_remnant",
         "Tomb Raider"),
        ("scylla", "scylla", "Acropolis", "cataclysm:music_disc_scylla", "Stormcaller"),
    ]
    for i, (slug, ent, where, icon, tag) in enumerate(bosses):
        c.branch(-4 + i)
        title = ent.replace("the_", "The ").replace("_", " ").title()
        c.q(f"cata_{slug}", title, f"k:cataclysm:{ent}", f"Slay {title} in the {where}.",
            deps="ender_dragon" if slug in ("ender_guardian",) else "finale_start",
            icon=icon, boss=True, rewards=[title_tag(tag)])
    c.branch(5)
    c.q("alpha_yeti", "The Alpha Yeti", "k:twilightforest:alpha_yeti", "Slay the Alpha Yeti in its cave.",
        deps="finale_start", icon="twilightforest:alpha_yeti_trophy", boss=True,
        rewards=[title_tag("Yeti Tamer")])
    c.q("snow_queen", "The Snow Queen", "k:twilightforest:snow_queen",
        "Slay the Snow Queen in the Aurora Palace.", icon="twilightforest:snow_queen_trophy", boss=True,
        rewards=[title_tag("Queenslayer")])
    c.branch(6)
    c.q("apostle", "The Apostle", "k:goety:apostle", "Slay Goety's Apostle in the Nether.",
        deps="finale_start", icon="minecraft:blaze_powder", boss=True, rewards=[title_tag("Heretic's Bane")])
    c.q("ender_keeper", "The Ender Keeper", "k:goety:ender_keeper", "Slay the Ender Keeper.",
        deps="ender_dragon", icon="minecraft:ender_eye", boss=True, rewards=[title_tag("Keeper's End")])
    c.q("heresiarch", "The Heresiarch", "k:goety:heresiarch", "Slay the Heresiarch.", deps="apostle",
        icon="minecraft:wither_rose", boss=True, rewards=[title_tag("Last Heresy")])
    c.branch(0)
    c.q("capstone", "Archmage", "c", "Every boss in the Cataclysm has fallen. Tick the box to claim the title.",
        deps=["cata_" + b[0] for b in bosses] + ["snow_queen", "ender_keeper", "heresiarch"],
        icon="minecraft:nether_star", shape="heart", size=2.5,
        rewards=[title_tag("Archmage"), "team:loot:cataclysm", "item:minecraft:dragon_head"])


def builders_guild():
    c = Chapter("guild_s1", "Builder's Guild: Season 1", GUILD, "buildinggadgets2:gadget_building", "side",
                plain="Open-ended commissions. Build, then tick the box. No checks, no rush.")
    c.q("guild_join", "Join the Guild", "c", "Tick the box. Every commission here is optional.",
        deps=[], icon="minecraft:bricks", shape="hexagon", size=1.5, rewards=["choice:guild_tools"])
    commissions = [
        ("guild_well", "The Village Well", "Build a well for your town.", "minecraft:bucket"),
        ("guild_market", "Market Stalls", "Build three market stalls.", "minecraft:emerald"),
        ("guild_tower", "The Mage Tower", "Build a tower for your spell work, at least 30 blocks tall.",
         "minecraft:amethyst_block"),
        ("guild_library", "The Library", "Build a library with at least 30 bookshelves.", "minecraft:bookshelf"),
        ("guild_garden", "Herb Garden", "Build a walled herb garden.", "minecraft:flowering_azalea"),
        ("guild_bridge", "A Bridge", "Build a bridge across a river or ravine.", "minecraft:oak_planks"),
        ("guild_tavern", "The Tavern", "Build a tavern with a bar and seating.", "farmersdelight:cooking_pot"),
        ("guild_portal", "The Portal Hall", "Build a hall for your portals and waystones.",
         "minecraft:crying_obsidian"),
        ("guild_dock", "The Docks", "Build a dock with at least one boat.", "minecraft:oak_boat"),
        ("guild_statue", "A Statue", "Build a statue of anything you like.", "minecraft:calcite"),
        ("guild_lighthouse", "Lighthouse", "Build a lighthouse on the coast.", "minecraft:sea_lantern"),
        ("guild_greenhouse", "Greenhouse", "Build a glass greenhouse.", "minecraft:glass"),
        ("guild_stable", "Stables", "Build stables for your horses.", "minecraft:hay_block"),
        ("guild_skyship", "A Ship in the Sky", "Build an airship, docked high above your town.",
         "minecraft:white_wool"),
        ("guild_wonder", "A Wonder", "Build something your team is proud of. Anything at all.",
         "minecraft:beacon"),
    ]
    for i, (slug, title, plain, icon) in enumerate(commissions):
        c.branch((i % 5) - 2)
        rewards = ["team:loot:guild"]
        if slug == "guild_wonder":
            rewards.append("team:choice:guild_tools")
        c.q(slug, title, "c", plain + " Tick the box when done.", deps="guild_join", icon=icon,
            optional=True, rewards=rewards)


def workshop():
    c = Chapter("workshop", "The Workshop", SIDE, "computercraft:computer_advanced", "side",
                plain="CC: Tweaked computers, turtles and peripherals.")
    c.q("computer", "A Computer", "i:computercraft:computer_normal", "Craft a computer.", deps=[],
        shape="hexagon", size=1.5, rewards=["loot:tinker"])
    c.q("first_program", "Hello, World", "c",
        "Open the computer and type: print(\"Hello\"). Then type edit hello to write your first program.",
        icon="computercraft:disk")
    c.q("disk_drive", "A Disk Drive", "i:computercraft:disk_drive", "Craft a disk drive.", deps="computer")
    c.q("printer", "Printer", "i:computercraft:printer", "Craft a printer.", deps="computer")
    c.q("speaker", "Speaker", "i:computercraft:speaker", "Craft a speaker.", deps="computer")
    c.branch(-2)
    c.q("turtle", "A Turtle", "i:computercraft:turtle_normal", "Craft a turtle.", deps="computer")
    c.q("mining_turtle", "A Mining Turtle", "c",
        "Craft a turtle with a diamond pickaxe and run 'excavate 5'. Tick the box when it digs.",
        icon="minecraft:diamond_pickaxe", rewards=["loot:tinker"])
    c.q("wireless_modem", "Wireless", "i:computercraft:wireless_modem_normal", "Craft a wireless modem.",
        deps="computer")
    c.q("pocket", "A Pocket Computer", "i:computercraft:pocket_computer_normal", "Craft a pocket computer.")
    c.q("monitor", "Monitors", "i:computercraft:monitor_advanced*4", "Craft four advanced monitors.",
        deps="computer")
    c.branch(2)
    c.q("peripheral_casing", "Peripheral Casing", "i:advancedperipherals:peripheral_casing",
        "Craft an Advanced Peripherals casing.", deps="computer")
    c.q("chat_box", "The Chat Box", "i:advancedperipherals:chat_box", "Craft a chat box.")
    c.q("doorbell", "A Doorbell", "c",
        "Hook a chat box and a player detector to a computer. Make it announce visitors in chat.",
        icon="minecraft:bell", deps=["chat_box", "player_detector"], rewards=["loot:tinker"])
    c.q("player_detector", "Player Detector", "i:advancedperipherals:player_detector",
        "Craft a player detector.", deps="peripheral_casing")
    c.q("env_detector", "Environment Detector", "i:advancedperipherals:environment_detector",
        "Craft an environment detector.", deps="peripheral_casing")
    c.q("inventory_manager", "Inventory Manager", "i:advancedperipherals:inventory_manager",
        "Craft an inventory manager.", deps="peripheral_casing")
    c.branch(4)
    c.q("storage_terminal", "Storage Terminal", "i:toms_storage:storage_terminal",
        "Craft a Tom's Storage terminal.", deps=[])
    c.q("inventory_connector", "Inventory Connector", "i:toms_storage:inventory_connector",
        "Craft an inventory connector.")
    c.q("inventory_cable", "Inventory Cable", "i:toms_storage:inventory_cable*16", "Craft 16 inventory cables.")
    c.q("crafting_terminal", "Crafting Terminal", "i:toms_storage:crafting_terminal",
        "Craft a crafting terminal.", deps="storage_terminal")
    c.q("dashboard", "Storage Dashboard", "c",
        "Show your storage on a monitor with a computer. Tick the box when it works.",
        deps=["crafting_terminal", "monitor", "inventory_manager"], icon="computercraft:monitor_advanced",
        shape="hexagon", rewards=["loot:tinker"])
    c.branch(-4)
    c.q("tp_gpu", "A Graphics Card", "i:toms_peripherals:gpu", "Craft a Tom's Peripherals GPU.", deps="computer")
    c.q("tp_monitor", "A Bigger Screen", "i:toms_peripherals:monitor*4", "Craft four Tom's monitors.")
    c.q("tp_keyboard", "Keyboard", "i:toms_peripherals:keyboard", "Craft a keyboard.")


def atlas():
    c = Chapter("atlas", "Explorer's Atlas", SIDE, "explorerscompass:explorerscompass", "side",
                plain="Structures, dimensions and the loot inside them.")
    c.q("atlas_start", "An Explorer's Life", "c", "Tick the box. The world is bigger than it looks.", deps=[],
        icon="minecraft:filled_map", shape="hexagon", size=1.5, rewards=["loot:explorer"])
    c.q("explorers_compass", "Explorer's Compass", "i:explorerscompass:explorerscompass",
        "Craft an Explorer's Compass. It points to any structure.")
    c.q("natures_compass", "Nature's Compass", "i:naturescompass:naturescompass",
        "Craft a Nature's Compass. It points to any biome.", deps="atlas_start")
    c.branch(-2)
    c.q("lootr_1", "A Chest Just for You", "a:lootr:1chest",
        "Open a Lootr chest. Each player gets their own loot.", deps="atlas_start", icon="minecraft:chest")
    c.q("lootr_10", "Ten Chests", "a:lootr:10loot", "Open ten Lootr containers.", icon="minecraft:chest")
    c.q("lootr_25", "Twenty-Five Chests", "a:lootr:25loot", "Open twenty-five Lootr containers.",
        icon="minecraft:chest", rewards=["loot:explorer"])
    c.q("lootr_100", "A Hundred Chests", "a:lootr:100loot", "Open a hundred Lootr containers.",
        icon="minecraft:ender_chest", rewards=["loot:explorer"])
    c.branch(2)
    c.q("dungeon_zombie", "A Zombie Dungeon", "a:betterdungeons:zombie_dungeon", "Find a zombie dungeon.",
        deps="explorers_compass", icon="minecraft:zombie_head")
    c.q("dungeon_skeleton", "A Skeleton Dungeon", "a:betterdungeons:skeleton_dungeon", "Find a skeleton dungeon.",
        icon="minecraft:skeleton_skull")
    c.q("dungeon_spider", "A Spider Cave", "a:betterdungeons:spider_dungeon", "Find a spider dungeon.",
        icon="minecraft:cobweb")
    c.q("dungeon_all", "Every Dungeon", "a:betterdungeons:all_dungeons", "Find every kind of Better Dungeons dungeon.",
        icon="minecraft:mossy_cobblestone", rewards=["loot:explorer"])
    c.branch(3)
    c.q("tavern", "The Tavern", "a:nova_structures:adventure/find_tavern", "Find a tavern.",
        deps="explorers_compass", icon="minecraft:barrel")
    c.q("witch_villa", "The Witch's Villa", "a:nova_structures:adventure/find_witch_villa", "Find a witch villa.",
        icon="minecraft:cauldron")
    c.q("illager_manor", "The Illager Manor", "a:nova_structures:adventure/find_illager_manor",
        "Find an illager manor.", icon="minecraft:crossbow")
    c.q("lone_citadel", "The Lone Citadel", "a:nova_structures:adventure/find_lone_citadel",
        "Find a lone citadel.", icon="minecraft:stone_bricks")
    c.branch(-3)
    c.q("nether", "The Nether", "a:minecraft:story/enter_the_nether", "Enter the Nether.", deps="atlas_start",
        icon="minecraft:obsidian")
    c.q("fortress", "A Fortress", "a:minecraft:nether/find_fortress", "Find a Nether fortress.",
        icon="minecraft:nether_bricks")
    c.q("bastion", "A Bastion", "a:minecraft:nether/find_bastion", "Find a bastion remnant.",
        icon="minecraft:gilded_blackstone")
    c.q("nether_keep", "The Nether Keep", "a:nova_structures:nether/find_keep", "Find a Nether keep.",
        icon="minecraft:blackstone")
    c.branch(-4)
    c.q("end", "The End", "a:minecraft:story/enter_the_end", "Enter the End.", deps="nether",
        icon="minecraft:end_stone")
    c.q("end_city", "An End City", "a:minecraft:end/find_end_city", "Find an End city.",
        icon="minecraft:purpur_block")
    c.q("end_castle", "The End Castle", "a:nova_structures:end/find_end_castle", "Find an End castle.",
        icon="minecraft:end_stone_bricks", rewards=["loot:explorer"])
    c.branch(4)
    c.q("atlas_tf", "The Twilight Forest", "d:twilightforest:twilight_forest", "Enter the Twilight Forest.",
        deps="atlas_start", icon="minecraft:oak_sapling")
    c.q("magic_map", "A Magic Map", "a:twilightforest:magic_map", "Make a Twilight Forest magic map.",
        icon="minecraft:map")
    c.q("atlas_undergarden", "The Undergarden", "d:undergarden:undergarden", "Enter the Undergarden.",
        deps="atlas_start", icon="minecraft:stone_bricks")
    c.q("adventuring_time", "Adventuring Time", "a:minecraft:adventure/adventuring_time",
        "Visit every overworld biome.", deps="natures_compass", icon="minecraft:diamond_boots",
        shape="hexagon", rewards=["loot:explorer", "loot:explorer"])


def bestiary():
    c = Chapter("bestiary", "Bestiary", SIDE, "l2hostility:hostility_detector", "side",
                plain="Hostile mobs grow stronger. Learn their traits and hunt the monsters of the wild.")
    c.q("bestiary_start", "Know Your Enemy", "a:l2hostility:hostility/root",
        "Mobs gain levels and traits the further you go. Meet your first.", deps=[],
        icon="minecraft:zombie_head", shape="hexagon", size=1.5)
    c.q("detector", "Read the Signs", "a:l2hostility:hostility/detector", "Use a Hostility Detector.",
        icon="l2hostility:hostility_detector")
    c.q("glasses", "Detector Glasses", "i:l2hostility:detector_glasses",
        "Craft Detector Glasses to see mob traits.")
    c.q("kill_first", "First Trait", "a:l2hostility:hostility/kill_first", "Kill a mob with a trait.",
        icon="minecraft:iron_sword", rewards=["loot:hunter"])
    c.q("kill_5_traits", "Five Traits", "a:l2hostility:hostility/kill_5_traits",
        "Kill a mob with five traits.", icon="minecraft:diamond_sword")
    c.q("kill_10_traits", "Ten Traits", "a:l2hostility:hostility/kill_10_traits",
        "Kill a mob with ten traits.", icon="minecraft:netherite_sword", rewards=["loot:hunter"])
    c.branch(-2)
    c.q("sanity", "A Bottle of Sanity", "i:l2hostility:bottle_of_sanity",
        "Brew a Bottle of Sanity. It lowers your own hostility level.", deps="detector")
    c.q("chaos_ingot", "Chaos Ingot", "a:l2hostility:hostility/ingot", "Make a chaos ingot.",
        icon="l2hostility:chaos_ingot")
    c.q("miracle", "A Miracle", "a:l2hostility:hostility/miracle", "Earn L2 Hostility's miracle advancement.",
        icon="minecraft:totem_of_undying")
    c.branch(2)
    for slug, ent, title, plain, icon in [
        ("frostmaw", "mowziesmobs:frostmaw", "The Frostmaw", "Slay a Frostmaw in a snowy biome.",
         "minecraft:blue_ice"),
        ("wroughtnaut", "mowziesmobs:ferrous_wroughtnaut", "The Wroughtnaut",
         "Slay the Ferrous Wroughtnaut in its underground hall.", "minecraft:iron_axe"),
        ("umvuthi", "mowziesmobs:umvuthi", "Umvuthi", "Slay Umvuthi in a savanna.", "minecraft:gold_block"),
        ("sculptor", "mowziesmobs:sculptor", "The Sculptor", "Defeat the Sculptor on its peak.",
         "minecraft:chiseled_stone_bricks"),
    ]:
        c.q(slug, title, f"k:{ent}", plain, deps="bestiary_start" if slug == "frostmaw" else PREV,
            icon=icon, rewards=["loot:hunter"])
    c.branch(3)
    for slug, ent, title, plain, icon in [
        ("pumpkinhead", "born_in_chaos_v1:lord_pumpkinhead", "Lord Pumpkinhead", "Slay Lord Pumpkinhead.",
         "minecraft:carved_pumpkin"),
        ("bonescaller", "born_in_chaos_v1:supreme_bonescaller", "The Supreme Bonescaller",
         "Slay the Supreme Bonescaller.", "minecraft:bone_block"),
        ("krampus", "born_in_chaos_v1:krampus", "Krampus", "Slay Krampus.", "minecraft:chain"),
    ]:
        c.q(slug, title, f"k:{ent}", plain, deps="bestiary_start" if slug == "pumpkinhead" else PREV,
            icon=icon, rewards=["loot:hunter"])


def hearth():
    c = Chapter("hearth", "Hearth", SIDE, "farmersdelight:cooking_pot", "side",
                plain="Farmer's Delight: good food keeps a mage on their feet.")
    c.q("hearth_start", "The Kitchen", "i:farmersdelight:cooking_pot", "Craft a cooking pot.", deps=[],
        shape="hexagon", size=1.5)
    c.q("skillet", "The Skillet", "i:farmersdelight:skillet", "Craft a skillet.")
    c.q("stove", "The Stove", "i:farmersdelight:stove", "Craft a stove.")
    c.q("cabinet", "Kitchen Cabinet", "i:farmersdelight:oak_cabinet", "Craft an oak cabinet.")
    c.branch(-2)
    c.q("rice", "Rice", "i:farmersdelight:rice*8", "Grow eight rice. Plant it in shallow water.",
        deps="hearth_start")
    c.q("tomato", "Tomatoes", "i:farmersdelight:tomato*8", "Grow eight tomatoes.")
    c.q("cabbage", "Cabbage", "i:farmersdelight:cabbage*8", "Grow eight cabbages.")
    c.q("onion", "Onions", "i:farmersdelight:onion*8", "Grow eight onions.")
    c.branch(2)
    meals = [
        ("beef_stew", "Beef Stew"), ("chicken_soup", "Chicken Soup"), ("fried_rice", "Fried Rice"),
        ("pasta_with_meatballs", "Pasta and Meatballs"), ("fish_stew", "Fish Stew"),
        ("ratatouille", "Ratatouille"), ("stuffed_pumpkin_block", "A Stuffed Pumpkin"),
        ("shepherds_pie_block", "Shepherd's Pie"),
    ]
    for i, (iid, title) in enumerate(meals):
        c.q(f"meal_{iid}", title, f"i:farmersdelight:{iid}", f"Cook {title.lower().removeprefix('a ')}.",
            deps="hearth_start" if i == 0 else PREV, rewards=["loot:hearth"] if i % 3 == 2 else [])
    c.branch(0)
    c.q("feast", "A Feast", "i:farmersdelight:roast_chicken_block", "Cook a roast chicken feast for your team.",
        deps=[f"meal_{m[0]}" for m in meals[-2:]] + ["onion"], shape="hexagon", size=1.5,
        rewards=["team:loot:hearth"])


def define():
    tables()
    prologue()
    act1()
    arcane()
    occult()
    natural()
    act3()
    finale()
    builders_guild()
    workshop()
    atlas()
    bestiary()
    hearth()


def main(argv):
    define()
    if argv[1:] == ["--dump-outline"]:
        dump_outline()
        return 0
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    build(argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
