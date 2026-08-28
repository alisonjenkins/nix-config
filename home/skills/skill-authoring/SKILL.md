---
name: skill-authoring
description: Use when adding, editing, splitting or reorganising a skill, deciding whether something should be a skill at all, or working out why a skill is not firing when it should. Carries the family pattern used here, how to write a description that actually matches, which frontmatter fields are portable versus Claude-Code-only, what a skill costs in context, and how skills get installed from this repo.
---

# Skill authoring

## Should this be a skill?

A skill earns its place when the same instructions, checklist, or procedure
keeps getting pasted into chat, or when a section of an instructions file has
grown from *facts* into a *procedure*.

- **Facts about the project** → instructions file (`CLAUDE.md`, `AGENTS.md`).
  Always in context, so keep it short.
- **A procedure** → a skill. The body loads only when invoked, so long
  reference material costs almost nothing until needed.
- **Something the harness must do automatically** → a hook, not a skill. A
  skill cannot make itself run on an event.
- **A one-off** → neither. Just do it.

## Corrections belong here, not only in memory

When the user corrects how you work, and the correction would hold next month
on a different repo, it belongs in a skill. A memory records that it happened
once; a skill changes what happens by default.

The test is whether the correction survives its context. "Ask before mutating
live infrastructure" and "probe `sudo -n` before deferring" generalise, so they
go in a family. "This host has 3.8GB of RAM" does not, so that stays a memory.

Put it in the narrowest place that still catches the case: a language file
beats the family parent, and the family parent beats an always-loaded
instructions file. Reserve the instructions file for rules that must hold even
when no skill is loaded.

## The family pattern

Skills are discovered at exactly one level: `~/.claude/skills/<name>/SKILL.md`
and `.claude/skills/<name>/SKILL.md`. Deeper nesting is **never** discovered.
Hierarchy therefore lives in the **body**, not the directory layout:

```
skills/<family>/
  SKILL.md            # general guidance + routing table
  <child>.md          # loaded on demand, only when the table points at it
  languages/<lang>.md
```

The parent holds what is true regardless of variant. Each child holds one
variant's specifics. The parent ends with a routing table so the model knows
which child to read and when:

| Working in | Read |
|---|---|
| `*.rs`, `Cargo.toml` | [languages/rust.md](languages/rust.md) |

This is the whole disclosure mechanism, and it is why the parent's description
must carry trigger keywords for **every** child: the parent is the only thing
in the listing, so if it does not fire, no child is ever reached.

Existing families: `programming`, `testing`, `git`, `review`, `infra`,
`documents`, `web-ui`, and this one.

## Routing

| Doing | Read |
|---|---|
| Writing the description, naming, deciding parent vs leaf | [conventions.md](conventions.md) |
| Frontmatter fields, and which survive outside Claude Code | [frontmatter.md](frontmatter.md) |
| What a skill costs in context, and how to make it cost less | [context-budget.md](context-budget.md) |
| Installing a skill from this repo (Nix wiring, opencode) | [wiring.md](wiring.md) |

## Related skills

- `/skill-creator`: scaffolds a new skill directory interactively. Claude Code
  only; it is set to `name-only` so this family carries its triggers.
- `superpowers:writing-skills`: the authoring discipline and how to verify a
  skill actually works before deploying it.
