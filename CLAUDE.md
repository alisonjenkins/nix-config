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

### Skills

Specialized skills in `.claude/skills/` (read the skill before touching relevant code):
- **`nix-config-workflows`** (`.claude/skills/nix-config-workflows/SKILL.md`): how to modify configs, add hosts, modules, flake-modules, secrets. Auto-loads for configuration work.
- **`pins`** (`.claude/skills/pins`): registry (`pins/registry.json`), review deadlines, and probes (`scripts/pins.py`, ADR 0051). Read before adding, extending, or removing any pin.
- **Path-scoped skills** (auto-load on their paths):
  - `minecraft-modpack-packaging` (`pkgs/create-*-server`)
  - `beatsaber-modding` (`pkgs/beatsaber-mods`, `home/modules/beatsaber`)
  - `helldivers2-modding` (`pkgs/arsenal`, `pkgs/hd2-repatcher`, `home/modules/helldivers2-mods`)

### Subsystems relevant to Claude Code

- **`claude-monitor`** (AI control centre): session monitoring and token tracking (`docs/ai-control-centre.md`, ADRs 0040, 0041).
- **`modules.memoryRecall`** (`home/modules/memory-recall`, `scripts/retrieval-eval`): agent memory retrieval (`docs/memory-recall.md`, ADRs 0029, 0030).
