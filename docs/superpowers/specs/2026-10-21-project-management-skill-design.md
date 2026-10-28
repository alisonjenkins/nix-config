# Project management skill: design

Status: approved by the user in conversation, 2026-10-21T00:00:00Z. Not yet implemented.

## Problem

There is no shared skill for breaking a project into tasks, tracking those tasks in a ticket system, or writing project documentation. Each session redoes this by hand with many `gh` calls, which burns tokens and gives inconsistent results.

## Goal

A shared skill, `project-management`, that:

- breaks projects into epics and tasks with sizes, dependencies and acceptance criteria;
- tracks tasks in a ticket system through scripts with compact output;
- produces project documentation (charter, plan, status report, retro).

It follows the family pattern: a parent `SKILL.md` with a routing table, child markdown files loaded on demand, and `scripts/` with bats tests.

## Non-goals (v1)

- Jira, GitLab and Linear backends. The design leaves room for them. None is built.
- Replacing `speckit-*` skills or writing a feature's `spec.md`, `plan.md` or `tasks.md`. See "Spec-kit interaction".
- Modifying `speckit-taskstoissues`. It is installed by `speckit-init`; this skill coexists with it.
- Persisted configuration of any kind (see "Backend selection").

## Location and wiring

`home/skills/project-management/`. `flake-modules/lib.nix` auto-discovers every directory under `home/skills/`, so no Nix edits are needed. The existing `skills-lint` and `skills-triggers` checks apply.

## Layout

```text
home/skills/project-management/
  SKILL.md             when to use, mandate, backend rules, routing table
  triggers.json        fire / no-fire phrases
  breakdown.md         project to epics to tasks; sizing; dependencies; acceptance criteria
  tracking.md          backend-neutral workflow, verb contract, token rules
  docs.md              charter, plan, status report, retro templates
  github.md            GitHub Issues specifics (labels, milestones, epics, limits)
  local.md             markdown tracker format
  scripts/
    pm                 entrypoint and dispatcher
    lib/               shared shell helpers (alias table, URL parsing, TSV output)
    backends/
      github/          alias, status.sh, list.sh, show.sh, update.sh, sync-plan.sh
      local/           alias, status.sh, list.sh, show.sh, update.sh, sync-plan.sh
    tests/
      contract.bats    same verb cases against every backend
      dispatch.bats    alias and routing rules
      github/*.bats    fake gh on PATH
      local/*.bats
```

## Backend selection

The scripts hold no state and do no detection. The caller names the backend on every call.

```bash
pm -b g -r owner/name status
pm -b l -d docs/projects/foo list --state open
pm show https://github.com/owner/name/issues/12
```

Rules:

1. `-b` / `--backend` is required unless the first ref is a URL that identifies its backend. A missing or unknown value exits non-zero and prints the table: `error: -b required: g|github l|local`.
2. A `-b` value resolves in this order, with no prefix or fuzzy matching: an alias match, then a full backend name match, otherwise an error.
3. A full issue URL carries backend and repo, so `pm show <url>` needs no other flags.
4. Backend-specific flags belong to that backend: `-r/--repo` (github), `-d/--dir` (local). Each backend validates its own flags and reports a missing or bad one with a one-line error that names the flag. The dispatcher reads `-b` only before the verb; everything after the verb is passed to the backend untouched, so a value such as `--comment "-h"` is never mistaken for a dispatcher flag.
5. Environment equivalents (`PM_BACKEND`, `PM_REPO`, `PM_DIR`) exist for one-shot use. The agent should use flags, because shell state does not persist between Bash calls.
6. Line 1 of every output echoes the resolved target: `# backend=github repo=owner/name`. A wrong choice is visible at once.

Why no config file, git config or auto-detect: the user cannot keep config around, and a git remote on GitHub says nothing about where tickets live.

### Aliases

Each backend directory holds an `alias` file with one token matching `[A-Za-z]+`, case-sensitive. Single letters are the default. Multi-letter aliases are the fallback when letters are contested.

| Alias | Backend | Status |
|---|---|---|
| `g` | github | v1 |
| `l` | local | v1 |
| `j` | jira | reserved |
| `G` | gitlab | future |
| `L` | linear | future |

Lowercase goes to the first backend to claim a letter, uppercase to a later one with the same initial. The alias is file content, not a file name, so case-insensitive filesystems are not a problem.

The dispatcher builds the table by scanning `backends/*/alias`.

### How the agent knows the tracker

This lives in `SKILL.md`, not in code. In order:

1. The user said so, or pasted a ticket URL.
2. The repo's `CLAUDE.md`, `AGENTS.md` or README names it.
3. Otherwise ask the user once, in one line, and reuse the answer for the session.

Never infer the tracker from the git remote alone.

## Verb contract

Every backend implements the same verbs with the same output shape.

| Verb | Purpose | Output |
|---|---|---|
| `status` | counts by state, blocked, stale, next-up | one summary line plus a short TSV |
| `list` | compact task list; `--state`, `--label`, `--milestone`, `--assignee`, `--due-before <ISO8601 UTC>` | TSV: `id state title owner deps due est prio` |
| `show <id>` | one task; body truncated by default, `--full` to expand | key/value lines |
| `update <id>` | `--state`, `--label`, `--comment` on one task | one confirmation line |
| `sync-plan <file>` | create or update tracker items from a plan file or a speckit `tasks.md` | per-item `created`/`updated`/`exists`/`drift` lines |

Output rules:

- TSV or single-line summaries, never prose or JSON dumps.
- `due`, `est` and `prio` are optional and print as an empty field when unset, so the column count never changes. `due` is ISO8601 UTC, `est` is minutes (integer), `prio` is a small integer with 1 highest.
- Bodies are truncated unless `--full` is passed.
- GitHub reads use one GraphQL call with pagination, not N `gh` calls, in the same way as `git/scripts/pr-status.sh`.
- Timestamps are ISO8601 UTC.

### Idempotency and mutation

`sync-plan` is a dry run by default and mutates only with `--apply`, because creating issues is outward-facing. Each item carries a stable marker. Plan items use `pm:<slug>` ids on the task line. A GitHub epic carries a hidden `<!-- marker -->` first line in its body: `pm:spec-NNN` for a numbered spec directory, otherwise `pm:plan-<repo-relative path of the file, lowercased, with / and _ as ->`, so two projects never share one. A GitHub per-task issue is titled `Tnnn: description` and is tied to its tasks file by a `Source: <path>` line in its body or by an exactly matching title. Before creating, the script looks up the marker or title and prints `exists` instead of duplicating. If a lookup hit its cap (200 epics, 500 issues), `--apply` refuses, because a miss past the cap would create a duplicate. Re-running is safe. `update` is an explicit single change and takes effect at once; only `sync-plan` is a dry run by default.

`drift` lines report a disagreement the script will not resolve, for example `drift T005: issue closed, box open`. A drift line changes nothing. A human decides which side is right. `drift` also reports two epics that carry one marker, and an issue that starts with a task id but is tied neither to this file nor by an exact title.

## Backends

### github

- Uses `gh` only, and `gh issue list --json` for reads (one paged GraphQL call under the hood, capped at 200 issues; a truncation warning goes to stderr). No raw REST where `gh` has a subcommand.
- Issues, labels and milestones for tasks. Projects v2 fields are a follow-up (tracked in PENDING.md); v1 reads `est` and `prio` from labels and `due` from the milestone.
- Dependencies are recorded as `deps:` lines in the issue body and parsed back into the `deps` column.
- `due` comes from the issue's milestone due date. `est` and `prio` come from `est:<minutes>` and `prio:<n>` labels. Unset means an empty column.
- Epic and per-task behaviour for speckit input is described under "Spec-kit interaction".
- Detail goes in `github.md`: label scheme, epic format, the 200-issue cap and rate-limit behaviour.

### local

- Files under the `-d` directory: `charter.md`, `plan.md`, `tasks.md`, `status.md`.
- `tasks.md` uses the speckit line format: `- [ ] T001 [P] [US1] description`. One format serves plain projects and speckit features, so `pm status -b l -d specs/002-virtual-overview-column` works on an existing feature unchanged. `pm update` toggles the checkbox.
- Optional trailing fields on a task line: `owner:<name>`, `deps:T001,T002`, `due:<ISO8601 UTC>`, `est:<minutes>`, `prio:<n>`. Speckit-origin lines usually have none, so their `deps` column is empty and `status` cannot report them as blocked.
- The directory can be anywhere, including outside the working tree.
- Detail goes in `local.md`.

## Spec-kit interaction

This repo uses spec-kit: `specs/NNN-name/` holds `spec.md`, `plan.md` and `tasks.md`.

Ownership:

- speckit owns one feature's spec, plan and tasks. `pm` never writes them.
- `pm` owns the level above: project, epics, charter, status reports, and tracking across features and trackers.
- An epic is usually one speckit feature. The breakdown output tells the user to run `/speckit-specify` for that epic and links `specs/NNN-name` from the plan. It does not copy the content.
- Heuristic for `SKILL.md`: one code feature goes to speckit. Multi-feature, non-code or cross-team work goes to `pm`, which hands each feature down to speckit.

Tracking a spec's tasks in tickets:

- **Epic by default.** `pm sync-plan <specs/NNN/tasks.md> --apply` creates or updates one epic issue per spec. The title carries the spec ID and name, the body links `specs/NNN-name`, and the tasks appear as a GitHub task list (`- [x] T001 description`). GitHub renders progress with no extra issues. The epic carries the `pm:spec-NNN` marker, so a re-run edits the body in place.
- **Per-task issues are opt-in.** `--per-task T003,T007` (or `--per-task all`) creates `Tnnn: description` issues for tasks that need an assignee, discussion or cross-team visibility. The title format and the `Tnnn` dedup key match `speckit-taskstoissues`, so either tool can run first and the other sees `exists`.
- **One-way truth: file to issue.** `tasks.md` is versioned, reviewed in PRs and updated by `/speckit-implement`, so it is the source of truth. `sync-plan` pushes checkbox state to the epic body and closes per-task issues whose box is ticked. It never writes back to `tasks.md`. Disagreements print `drift` and change nothing.
- **Why not per-task by default.** A spec such as `002-virtual-overview-column` has dozens of tasks. One issue each is tracker noise and one API call per change. Task state also changes with every commit that ticks a box.
- **Token cost.** Epic mode is one read and at most one edit. Per-task mode is one GraphQL read plus one mutation per changed task. This replaces paging `list_issues` through MCP for deduplication.

## Downstream: time-management (separate skill, not part of v1)

Scheduling and timeboxing across projects is a sibling skill, `time-management`, with its own design cycle. This skill's only obligation is the read-only `list` contract above: `due`, `est` and `prio` are the inputs a scheduler needs, which is why they are in v1.

Direction of the sibling design, recorded so the contract does not drift:

- Prioritise (deterministic script, earliest deadline first, reason per row), timebox (script proposes, agent judges), calendar (backend per calendar, same stateless `-b` pattern, alias files, contract suite).
- Calendar writes are outward-facing: dry run by default, `--apply` to mutate, each event carries a `tm:<task-ref>` marker for idempotent re-runs.
- Backends planned: `ics` (no auth, first) and `google` (stub only).

The `google` backend is a stub. As of 2026-10-21 no Google Calendar tooling is reachable from the development machine: no MCP connector, no gateway tool, no `gcalcli`. The auth route (claude.ai connector or `gcalcli`) is undecided and deliberately deferred. Nothing in `project-management` depends on it.

## Documentation templates

`docs.md` carries templates for charter, plan, status report and retro. Hard-won lessons go to `docs/adr/` in the same change, following the repo rule. Each template is short and front-loads the conclusion.

## Token and delegation rules

- `status` and `list` are mechanical. `SKILL.md` tells the agent to run them through a cheap delegate where the delegation skill applies.
- Breakdown judgement (what the tasks are, how big, in what order) stays on the main loop.
- Examples in all docs use the short flags, since the agent copies what it reads. First mention of a flag shows the long form beside it.

## Portability

Shared skills run on many machines. The scripts need bash, `gh` (github backend only), `jq` and `git`. Each script probes with `command -v` and prints a clear error if a tool is missing. No absolute tool paths. Anything that differs between GNU and BSD userland (`date`, `sed`, `stat`) is avoided or wrapped, because macOS is in use.

## Testing

- `dispatch.bats`: alias resolution order, unknown backend error text, URL routing, flag precedence over env.
- Alias lint, as bats checks that must all pass:
  - every alias matches `^[A-Za-z]+$`;
  - no two backends share an alias (exact, case-sensitive);
  - no alias equals a different backend's full name;
  - every alias is no longer than its backend's full name.
- `contract.bats`: runs the same verb cases against every backend and checks output shape (header line, TSV column count of 8 for `list`, `due`/`est`/`prio` empty when unset, exit codes). A drifting backend fails here.
- Speckit input: a fixture copied from a real `specs/*/tasks.md` (checked and unchecked boxes, `[P]`, `[US#]` markers) must parse. Cases: epic created, epic updated in place on re-run, `--per-task` title matches `Tnnn: description`, a closed issue with an open box yields `drift` and no mutation, and `sync-plan` never modifies the input file.
- Per-backend suites: GitHub uses a fake `gh` on `PATH`, in the style of `git/scripts/tests/gh`. Local uses temp directories.
- `triggers.json` entries are checked by `skills-triggers-tests`; `lint-skills.sh` checks conventions.

## Build order (atomic commits)

Each step compiles and passes checks alone, and reverts cleanly.

1. Skeleton: `SKILL.md` with description and routing table, `triggers.json`.
2. `scripts/pm` dispatcher, `lib/`, alias scan, plus `dispatch.bats`.
3. Local backend, one verb per commit, each with tests.
4. GitHub backend, one verb per commit, each with tests.
5. `contract.bats`.
6. Child docs: `tracking.md`, `breakdown.md`, `docs.md`, `github.md`, `local.md`.
7. Wire skill into `README`/docs index if the repo has one; ADR for the stateless-backend decision.

## Assumptions

- Local tracker files default to a directory the caller passes with `-d`. There is no default path, so nothing forces files into a repo that cannot hold them.
- `gh` is authenticated on machines that use the github backend. The script checks and reports, and does not log in.
- Jira, GitLab and Linear are out of scope for v1.
