# Installing a skill from this repo

## Where a skill should live

| Scope | Location | Notes |
|---|---|---|
| Every project, every machine | `home/skills/<name>/` | Runtime-agnostic. Auto-discovered into `flake.lib.skills`, then linked into Claude Code *and* opencode. Spec-only frontmatter. |
| This repo only | `.claude/skills/<name>/` | Checked in. Claude-Code-only frontmatter is fine here. |
| One subtree of a monorepo | `<subdir>/.claude/skills/<name>/` | Loads the first time Claude touches a file in that subtree; appears as `<subdir>:<name>` when the name clashes. |

## The Nix wiring

`flake-modules/lib.nix` reads `home/skills/` and exposes each directory as
`flake.lib.skills.<name>`. Adding a directory there is the whole registration
step, and no consumer needs editing.

`home/programs/claude-code/default.nix` then assembles `allSkills`:

- Each **anthropic** skill and each **shared family** is one directory, so both
  go through `linkFarm`, which preserves the directory name.
- The **packages** that ship many skills (`cavemanPkg`, `claude-statusbar`,
  `speckitInitSkill`) are *parents* of skill directories, so `symlinkJoin`
  merging their contents is correct.

**This distinction is load-bearing.** `symlinkJoin` merges directory
*contents*: pointing it at a skill directory flattens that skill into the root,
one arbitrary `SKILL.md` wins, and every skill's `scripts/`, `reference/`, and
`examples/` collide. The symptom is skills that silently do not exist.

`home.file` does not remove files a previous generation created, so after
changing the layout, delete stale directories in `~/.claude/skills/` by hand.

## opencode

`home/programs/opencode/default.nix` links every shared skill automatically
from the same flake output:

```nix
// lib.mapAttrs' (
  name: path: lib.nameValuePair "opencode/skills/${name}" { source = path; }
) inputs.self.lib.skills
```

Note it links whole **directories**. Linking a single `SKILL.md` would silently
drop every child file: the skill would load and its routing table would point
at nothing.

## After adding a skill

1. `git add` it. Flakes ignore untracked files, and the error does not say so.
2. `just build <hostname>`: proves it evaluates.
3. `just switch`, then start a **new** session: the listing is built at
   startup.
4. Confirm it is there and that it fires from a phrase you would really use,
   not from typing its name.
