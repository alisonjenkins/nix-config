---
name: claude-code-mods
description: >-
  How this repo manages Claude Code mods (plugins of function hooks: live
  panes, status-line entries, toasts, tool-call/prompt hooks, slash commands)
  declaratively via home/claude-mods and programs.claude-code.plugins. Use when
  adding, editing, promoting or debugging a Claude mod, or when the bundled
  plugin-authoring skill is loaded and the mod should persist across sessions
  and machines instead of living in ~/.claude/dev-mods.
paths:
  - "home/claude-mods/**"
---

# Claude Code mods, managed by Nix

The bundled `plugin-authoring` skill is the API reference (hooks, `$` nouns,
`ui.render`, `$.state` contracts, validate/test). Load it for that. It writes
mods to `~/.claude/dev-mods/<session-id>/<mod>/`: per-session, outside git,
and gone from the picture once the session ends. This skill covers the rest:
getting a mod into the repo so every host gets it, like skills.

## Layout

| What | Where |
|---|---|
| A mod | `home/claude-mods/<mod-name>/` (one directory per mod) |
| Auto-discovery | `flake.lib.mods` in `flake-modules/lib.nix` (same as `flake.lib.skills`) |
| Loading | `programs.claude-code.plugins` in `home/programs/claude-code/default.nix` appends `lib.attrValues inputs.self.lib.mods` |

Adding a directory is the whole registration step. Inside, the mod is exactly
what `plugin-authoring` describes:

```
home/claude-mods/<mod-name>/
  .claude-plugin/plugin.json      # name, version, description, optional "types"
  hooks/hooks.json                # { "modules": ["./register.tsx"] }
  hooks/register.tsx              # export const register: Register = (on, options) => {...}
  hooks/*.test.ts                 # at least one; run with `claude plugin test`
  types/index.d.ts                # only if the mod uses $.state
```

The engine writes `.claude-plugin/types/` into the mod folder for the editor.
It is gitignored; never commit it.

## Workflow

1. **Prototype** with `plugin-authoring` in `~/.claude/dev-mods/...`. Hot
   reload gives the fast loop; no rebuild needed.
2. **Promote**: copy the mod folder (without `.claude-plugin/types/`) to
   `home/claude-mods/<mod-name>/`. `git add` it before any `nix build`/`eval`
   (flake only sees tracked files).
3. **Validate from the repo copy**: `claude plugin validate home/claude-mods/<mod-name>`
   then `claude plugin test home/claude-mods/<mod-name>`.
4. **Apply**: `just test` (temporary) or `just switch`. The mod ships as a
   read-only store path via `--plugin-dir`, so it does NOT hot-reload.
   Edit in the repo, rebuild, restart the session.
5. **Iterating on a promoted mod**: run `claude --plugin-dir
   $PWD/home/claude-mods/<mod-name>` from the repo for a live-editable copy,
   or move it back to dev-mods. The nix-loaded copy of the same name competes
   with it; disable the nix one by testing on a host/branch without it, or
   rename the dev copy.

## Rules

- Do not leave a mod only in `~/.claude/dev-mods`; that is a scratch space.
  Tell the user the repo path, not the dev-mods path, as the deliverable.
- Mods are global: they load into every session and subagent on every host
  with the home module. Keep per-session cost low, and no machine-specific
  paths or tool assumptions (shared config runs on Linux and macOS; `$.process`
  commands must resolve via Nix store paths, not ambient PATH).
- Surface differs (`e.surface`: terminal, desktop, vscode, mobile). Use
  `$.ui.resolve(e)` elements, not assumptions.
- Subcommands (`claude plugin ...`, `mcp`, ...) get the injected
  `--plugin-dir` flags stripped by the dispatcher in
  `home/programs/claude-code/default.nix`; `claude plugin validate/test` run
  clean. Do not work around that.
- A mod a user wants only sometimes belongs behind a wrapper like `claude-dd`
  (extra `--plugin-dir`) rather than in `home/claude-mods/`, which is global.
- Engine API drifts per Claude Code release. After a `claude-code` bump, rerun
  `claude plugin validate` on every mod (types file is regenerated at load).
- Hard-won lessons go in `docs/adr/` in the same PR (repo convention).

## Verification

Eval only: `nix eval .#lib.mods --apply builtins.attrNames`. Build: `just
build`. `home/programs/claude-code` is shared by Linux and Darwin hosts, so
check one of each if the change touches wiring, not just a mod.
