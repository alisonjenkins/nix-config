# magic-vr-pack quest book

The FTB Quests book is generated, not hand-edited. The server build runs
`gen.py` into `config/ftbquests/quests/`, then checks every item, entity,
dimension and advancement ID in the output against the pack's jars
(`registry-ids` from `minecraft-modpack-tools`). A typo fails the build.

## Files

- `gen.py`: chapters, quests, tasks, rewards and loot tables, as Python.
- `lore.json`: Archmage Veyla's line for each quest, keyed by quest slug.
  The build fails if a slug has no line.

Each quest description is Veyla's line first, then the plain instruction.

## Editing

1. Change `gen.py`. Keep quest slugs stable: a quest's ID is a hash of its
   slug, so renaming a slug resets that quest's progress for every team.
2. Add a `lore.json` line for each new slug.
3. Preview without a full build:

   ```bash
   python3 gen.py /tmp/quests-out
   ```

4. Build the server package; the build runs the ID check.

`python3 gen.py --dump-outline` prints `slug|title|instruction` for every
quest, which is handy for writing lore lines.

## Rules the generator enforces

- No reward from a later act than the chapter's act. Side chapters count
  as act 0.
- No dependency cycles, no unknown dependencies, no duplicate slugs.
- Progress is per FTB team. No task or reward changes the world for
  other players.

## Builder's Guild: adding a season

Season 1 is the `builders_guild` function in `gen.py`: chapter `guild_s1`
in the "Builder's Guild" chapter group. To add Season 2:

1. Copy that function to `builders_guild_s2`, and give the chapter the slug
   `guild_s2` and the title "Season 2".
2. Keep the same group, "Builder's Guild", so it sits under Season 1.
3. Use new quest slugs (prefix them `guild2_`) so Season 1 progress stays.
4. Call the new function from `define()`, after `builders_guild()`.
5. Add the new slugs to `lore.json`.
