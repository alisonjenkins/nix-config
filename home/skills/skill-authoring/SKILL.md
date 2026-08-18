---
name: skill-authoring
description: Creating, structuring, and maintaining skills — the family pattern used here, how to write a description that actually fires, which frontmatter fields are portable versus Claude-Code-only, what a skill costs in baseline context, and how skills get installed from this repo. Use when adding a skill, editing an existing one, deciding whether something should be a skill at all, splitting a skill that has grown too large, or wondering why a skill is not triggering.
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

- `/skill-creator` — scaffolds a new skill directory interactively. Claude Code
  only; it is set to `name-only` so this family carries its triggers.
- `superpowers:writing-skills` — the authoring discipline and how to verify a
  skill actually works before deploying it.
