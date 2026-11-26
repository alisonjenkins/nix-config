# 0064. Keep skill ADRs at two levels, outside the skill files

- Status: Accepted
- Date: 2026-11-26

## Context

Skills under `home/skills/` state rules, not the reasons for them. A
reason that lives only in someone's head gets lost. The 2026-11-26 skills
audit found `home/skills/git/SKILL.md` preferring GitHub's rebase merge,
which drops commit signatures. The reason for the local-rebase rule had
never been written down, so a later edit reversed it unnoticed.

Writing the reasons into `SKILL.md` would fix that, but every line of a
skill body costs context each time the skill loads. Some decisions cover
the whole skills collection (layout, testing, deployment). Others cover
one skill's rules.

## Decision

Keep skill ADRs at two levels, both outside the deployed skill folders:

- **Collection-wide** decisions go in `docs/adr/`, in the repo's normal
  numbering, listed under Skills in `docs/adr/README.md`. A skill cites
  one as "(decision NNNN)".
- **Per-skill** decisions go in `docs/skills/<skill>/adr/NNNN-title.md`,
  numbered from 0001 for each skill, with the same template as
  `docs/adr/`. A skill cites one as "(decision <skill>/NNNN)".
  `docs/skills/README.md` lists every skill that has records.

Records are never edited to change history. A new record supersedes the
old one. Read the cited record before changing a rule that cites it.

## Alternatives rejected

- **Reasons inside `SKILL.md` or its topic files.** Costs context on
  every load, and is what Alison asked to avoid.
- **An `adr/` folder inside each skill.** Keeps them close, but
  home-manager copies the whole skill folder to `~/.claude/skills/`, so
  the records would ship with the skill and could be read as
  instructions.
- **Everything in `docs/adr/`.** One-skill decisions would crowd the
  repo-wide index and lose their grouping by skill.

## Consequences

- The first per-skill record is `docs/skills/git/adr/0001`, on merging by
  local rebase.
- The `skill-authoring` conventions point authors here.
- Lint does not check that a cited decision exists. A citation that names
  a missing record is a gap until a check is added.

## Evidence

- Alison's comments on the 2026-11-26 skills audit doc, asking for ADRs
  for the skills as a whole and for each skill.
- `home/skills/docs/structure.md`: keep the existing ADR folder and link
  a record from what depends on it.

## Revisit when

Skills deploy from a filtered copy that could exclude an `adr/` folder,
or the per-skill folders grow past a few records each and need their own
index pages.
