---
id: CLAUDE
aliases:
  - CLAUDE.md
tags: []
---
# CLAUDE.md

Imports tool-neutral repository instructions from AGENTS.md.

@AGENTS.md

## Claude Code

### Carried patches

- **noctalia** (`home/programs/linux-only/niri/default.nix`, `noctaliaPatch`): three fork-only patches from `alisonjenkins/noctalia`, pulled by commit. PR #1 (`session lock --grace <seconds>`, used by `pkgs/lock-session`), PR #2 (lock when no output is connected) and PR #3 (`lockscreen.grace_period_idle_only`, stacked on #1). They are not in the binary cache, so noctalia builds from source. Drop each once upstream has it. If a `nix flake update` of the `noctalia` input stops them applying, rebase the fork branch, push, then bump the `rev` and `hash`.

The skills in `.claude/skills/` auto-load for their work. `nix-config-workflows` (`.claude/skills/nix-config-workflows/SKILL.md`) covers modifying configs and adding hosts, modules, flake-modules and secrets. The path-scoped skills and the `pins` skill are listed under Subsystems in AGENTS.md.
