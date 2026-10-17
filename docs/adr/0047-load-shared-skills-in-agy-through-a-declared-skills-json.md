# 0047. Load the shared skills in agy through a declared skills.json

- Status: Accepted
- Date: 2026-10-17

## Context

Claude credits run low, so work moves to `agy` (Antigravity CLI). The skills
that carry the user's conventions (`git`, `programming`, `review`, `delegation`
and the rest of `home/skills/`) were linked only into `~/.claude/skills` and
`~/.agents/skills`, and the mandates (atomic commits, no AI attribution) only
into `~/.claude/CLAUDE.md`. Asked from a neutral directory which skills it could
see, `agy` answered `agy-customizations, antigravity-guide`: its two built-in
ones.

Facts found on 2026-10-17 (agy 1.2.9 and 1.2.16, headless `-p`):

- The documented per-user path `~/.gemini/antigravity-cli/skills/<name>` was not
  loaded in print mode (a probe skill there never appeared).
- A workspace `.agents/skills/<name>` was loaded by 1.2.16 but not by 1.2.9.
- A declared `skills.json` is loaded by both, from a workspace
  (`<repo>/.agents/skills.json`) and globally (`~/.gemini/config/skills.json`):
  `{"entries":[{"path":"/home/ali/.agents/skills"}]}` listed all 22 shared skills.
  The same file with `"path": "~/.agents/skills"` loaded none, with no error.
- Listing is not enough. Activating a skill reads its `SKILL.md`, which is
  outside the workspace, and a headless run answered `jetski: no output produced
  — a tool required the "read_file" permission that headless mode cannot prompt
  for, so it was auto-denied.` With `permissions.allow` set to
  `read_file(/home/ali/.agents/skills)` alone, reading a nested file
  (`programming/languages/shell.md`) was still denied, because the skills are
  symlinks into the Nix store and the rule is matched against the resolved path.
  Adding `read_file(/nix/store)` made both reads succeed.
- A skill whose frontmatter has an unquoted `description:` containing a colon
  fails to load (`mapping values are not allowed in this context`, per
  `agy changelog`). The shared skills use `>-` block descriptions.
- `~/.gemini/config/AGENTS.md` is read as an always-active global rule, with no
  frontmatter, capped at 24,000 bytes per file.

## Decision

`modules.antigravityCli` (`home/modules/antigravity-cli`) is a home-manager module
that `modules.desktop` turns on, through `home-manager.sharedModules`, for every
host with `modules.desktop.antigravityCli.enable` (default true; the work laptop
sets it false). It:

- Writes `~/.gemini/config/skills.json` declaring `~/.agents/skills` by absolute
  path, so the one set of shared skills serves Claude Code, opencode, Copilot and
  agy, with no second copy.
- Writes `~/.gemini/config/AGENTS.md` from `gitStrategy` and `workStyle` in
  `home/programs/shared-mandates.nix`. Model Routing is left out: it names which
  cheaper model Claude hands work to.
- Merges `read_file(<skills dir>)` and `read_file(/nix/store)` into
  `~/.gemini/antigravity-cli/settings.json` in an activation step, because `agy`
  rewrites that file itself (trusted workspaces, colour scheme) and a store
  symlink would be replaced or reset. The merge is `unique`, so it is idempotent,
  and it leaves the file alone if it is not valid JSON.

## Alternatives rejected

- **Link each skill into `~/.gemini/antigravity-cli/skills/`.** That path was not
  loaded in print mode, and it would duplicate the 22 links.
- **A workspace `.agents/skills`.** Not loaded by the pinned 1.2.9, and it only
  covers one repo.
- **`~/` in the skills.json path.** Accepted silently and loads nothing.
- **`--dangerously-skip-permissions` for skill reads.** It approves every tool
  call; two read rules cover the need.

## Consequences

- Skills written for Claude name Claude-only tools (the Skill and Agent tools);
  the knowledge in them applies, the tool instructions do not.
- `read_file(/nix/store)` lets `agy` read any store path without asking. The
  store is world-readable, and secrets are not kept in it.
- Project skills in a repo's `.claude/skills` are still not seen by `agy`; a
  per-repo `.agents/skills.json` pointing at them would do it, and needs the
  workspace route checked on the pinned version first.
- A repo's `CLAUDE.md` is not read by `agy`, which reads `AGENTS.md` or
  `GEMINI.md`.

## Evidence

- `agy -p "List the names of every skill you can see..."` from a neutral
  directory: `agy-customizations, antigravity-guide` before; with the global
  `skills.json`, `... consulting, debugging, delegation, design, documents, git,
  handoff, infra, ...` (24 names).
- `agy -p "Activate the programming skill, then read its languages/shell.md file
  and tell me the first heading"`: denied with no rule, denied with the skills
  rule only, `# Shell` with both rules.
- Built `ali-desktop`'s home-manager generation: `skills.json` and a 3.9 KB
  `AGENTS.md` without Model Routing present, the work laptop's generation has no
  `.gemini` files and no activation step, and the merge run on a copy of the real
  settings file kept its keys and was identical on a second run.

## Revisit when

`agy` loads `~/.agents/skills` or a global skills directory by itself in print
mode, or reads `~/.claude/skills`; then the `skills.json` is unnecessary. Or when
the allow rule syntax changes.
