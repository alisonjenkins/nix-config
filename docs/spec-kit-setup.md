# Spec-Kit Setup (Claude Code + GitHub Copilot CLI)

[Spec-kit](https://github.com/github/spec-kit) is packaged in this repo as
`pkgs/spec-kit` (the `specify` CLI) and wired up for both Claude Code and
GitHub Copilot CLI.

## How it is installed

- `pkgs/spec-kit/default.nix` builds the `specify` CLI from `github/spec-kit`.
- `home/programs/claude-code/default.nix` puts `specify` on `PATH`
  (`home.packages`) and ships the `/speckit-init` global skill.
- Nothing is pinned per-agent: the same CLI serves both integrations.

Spec-kit is **per-project**, unlike a Claude Code plugin. `specify init` writes
into the repo you run it in:

- `.specify/scripts/bash/` — the shell scripts the `/speckit-*` commands call
- `.specify/templates/` — spec / plan / tasks / checklist / constitution templates
- `.specify/memory/` — the project constitution
- the agent-specific command files (see below)

Initialisation needs **no network access** — templates and scripts are bundled
inside the CLI package.

## Claude Code

In a session, inside the repo you want to set up:

```
/speckit-init
```

That skill (`home/programs/claude-code/speckit-init-SKILL.md`) checks for an
existing `.specify/`, then runs:

```bash
specify init --here --force --integration claude
```

The Claude integration installs commands as **skills**, at
`.claude/skills/speckit-<name>/SKILL.md`. Commit `.specify/` and
`.claude/skills/speckit-*` along with the rest of the repo, and **restart the
session** — project skills are only read at startup.

Invocation uses hyphens, not dots:

```
/speckit-constitution   Define project principles
/speckit-specify        Write the spec (what to build)
/speckit-clarify        Resolve ambiguities in the spec
/speckit-plan           Technical implementation plan (how to build)
/speckit-tasks          Break the plan into tasks
/speckit-analyze        Cross-check spec / plan / tasks for drift
/speckit-implement      Execute
```

Also bundled: `/speckit-checklist`, `/speckit-converge`, `/speckit-taskstoissues`.

### Replaces cavekit

Claude Code previously loaded [cavekit](https://github.com/JuliusBrussee/cavekit)
as a nix plugin, giving `/ck:spec`, `/ck:build` and `/ck:check`. Spec-kit replaced
it — `plugins` in `home/programs/claude-code/default.nix` no longer lists it.
`pkgs/cavekit` still builds; re-adding `pkgs.cavekit` to that `plugins` list is
all it takes to bring the `/ck:*` commands back.

## GitHub Copilot CLI

```bash
cd /path/to/your/project
specify init . --integration copilot
```

This creates `.specify/` plus the Copilot-side command files under `.github/`.
Then:

```bash
gh copilot
```

Copilot's integration uses the dotted form:

```
/speckit.constitution Create principles focused on code quality...
/speckit.specify Build an application that...
/speckit.plan The application uses...
/speckit.tasks
/speckit.implement
```

Non-interactive:

```bash
gh copilot -p "/speckit.specify Build a CLI tool for..." --allow-all-tools
```

## Verifying

```bash
specify --version
specify init --help          # lists every --integration
ls .specify/scripts/bash     # after an init, in the target repo
```

## Updating spec-kit

1. Update `rev` in `pkgs/spec-kit/default.nix`
2. Update `hash`
3. `just switch`

Already-initialised repos keep the old bundled scripts until you re-run
`/speckit-init --force` (or `specify init --here --force --integration claude`)
in them.

## Troubleshooting

`/speckit-*` commands missing in Claude Code:

1. Confirm `.specify/` and `.claude/skills/speckit-*` exist in the repo — if not,
   run `/speckit-init`.
2. Restart the session; project skills load at startup only.

`/speckit.*` commands missing in Copilot CLI:

1. Confirm you ran `specify init . --integration copilot` in that project.
2. Restart the `gh copilot` session.
3. Check the command files were created under `.github/`.

`specify init` aborts on an agent-tool check: add `--ignore-agent-tools`. The
`claude` binary here is a nix wrapper and the check can miss it.

## Documentation

- [Spec-Kit GitHub](https://github.com/github/spec-kit)
- [Spec-Kit Documentation](https://github.github.io/spec-kit/)
- [Copilot CLI Docs](https://docs.github.com/copilot/how-tos/copilot-cli)
