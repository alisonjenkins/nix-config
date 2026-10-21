# 0049. Select the pm backend on every call

- Status: Accepted
- Date: 2026-10-21

## Context

The `project-management` skill needs one interface over several ticket systems: GitHub Issues now, Jira or Linear later, and a local markdown tracker. The first design remembered the choice in a `.pm.json` file in the repository, then in `git config` keys, then in a file under `$XDG_CONFIG_HOME`. The user rejected all three. A repository cannot always hold the file, and config kept elsewhere goes stale. Detecting the tracker from the git remote does not work either: code on GitHub says nothing about where the tickets live.

Read first: `docs/superpowers/specs/2026-10-21-project-management-skill-design.md`.

## Decision

`pm` holds no state and does no detection. The caller names the backend on every call with `-b`, as a case-sensitive alias (`g` for github, `l` for local) or the full name. A GitHub issue URL names its own backend and repository, so it needs no `-b`. The skill tells the agent where to learn the tracker: from the user, from a pasted URL, or from the repository's `CLAUDE.md` or `AGENTS.md`. If none of those say, it asks once.

Each backend is a directory under `home/skills/project-management/scripts/backends/` with one script per verb and an `alias` file. The `pm` dispatcher runs the right script. `lint-aliases.sh` rejects alias collisions, and `contract.bats` runs the same checks against every backend, so a backend that drifts from the verb contract fails CI.

Mutations are explicit. `sync-plan` is a dry run until `--apply`, and it refuses `--apply` when a lookup hit its cap, because an issue missing from a truncated list would be created twice.

## Consequences

- Every call carries `-b g -r owner/name`, a few extra tokens. The first line of every output echoes the resolved target, so a wrong choice is visible at once.
- Adding Jira or Linear is additive: a new backend directory, a doc and a free alias. No existing script changes.
- Nothing can go stale or be committed by accident, because nothing is stored.
- The GitHub backend reads with `gh issue list`, capped at 200 issues (500 for the per-task lookup). Larger repositories need narrower filters until pagination is added.
