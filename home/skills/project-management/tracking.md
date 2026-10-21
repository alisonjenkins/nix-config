# Tracking with pm

`pm` reads and updates tasks in a tracker through one interface. Name the backend on every call with `-b`.

## Verbs

| Verb | Does | Output |
|---|---|---|
| `status` | counts, blocked, stale, next task | `open=N done=N blocked=N stale=N`, then `next<TAB>id<TAB>title` |
| `list` | task rows | `id state title owner deps due est prio` |
| `show <id>` | one task | `key<TAB>value` lines, then a body (github) |
| `update <id>` | change one task | `updated ...` or `unchanged ...` |
| `sync-plan <file>` | create or update tracker items from a tasks file | `action<TAB>kind<TAB>ref<TAB>detail`, where action is `would-create`, `would-update`, `created`, `updated`, `exists` or `drift` |

Every output starts with `# backend=<name> ...`. If that line names the wrong tracker, stop.

## Flags

| Flag | Backend | Meaning |
|---|---|---|
| `-b g` / `--backend github` | all | pick the backend (`l` = local) |
| `-r owner/name` | github | repository |
| `-d <dir>` | local | directory holding `tasks.md` |
| `--state open\|done\|all` | list | default `open` |
| `--assignee`, `--due-before <ISO8601 UTC>` | list | filters |
| `--limit <n>`, `--offset <m>` | list | page the rows; when rows remain the last line is `# more=<left> next-offset=<m>` |
| `--max <n\|all>` | any verb, github only | raise the fetch cap (before the verb, like `-r`) |
| `--label`, `--milestone` | list, github only | passed to gh |
| `--state`, `--label`, `--unlabel`, `--comment` | update | local supports `--state` only |
| `--apply` | sync-plan | mutate; without it you get a dry run |
| `--per-task <ids\|all>` | sync-plan, github | also track tasks as `Tnnn: title` issues |
| `--full` | show | whole body instead of 20 lines |

A GitHub issue URL as an argument needs no `-b` or `-r` (unless `PM_BACKEND` is set; then the URL is passed through unchanged). Put `-b` before the verb: everything after the verb is passed to the backend untouched.

## Reading cheaply

1. `pm status` first. It is one call and often answers the question.
2. `pm list` with filters next. Rows are tab separated and short.
3. `pm show <id>` for one item. Add `--full` only when the body matters.

These reads are mechanical. Hand them to a cheap worker and keep the judgement here.

## Changing things

`update --state` is idempotent: it checks the current state first and prints `unchanged` if there is nothing to do. `--label`, `--unlabel` and `--comment` are not checked, so a retried `--comment` posts again. `sync-plan` is a dry run until `--apply`, so show the user the dry run before applying to GitHub.

## Spec-kit tasks

A speckit `tasks.md` (`- [ ] T001 [P] [US1] description`) is valid input for both backends.

- `pm -b g -r o/n sync-plan specs/NNN-name/tasks.md --apply` creates or updates one epic issue per spec. Tasks appear as a GitHub task list with a progress count. Re-running edits the epic in place.
- Add `--per-task T003,T007` (or `all`) for tasks that need an assignee or discussion. The titles match `speckit-taskstoissues`, so either tool can run first.
- State flows from the file to the issue, never back. If an issue was closed by hand while its box is open, the output has a `drift` line and nothing changes. Ask the user which side is right.
- `tasks.md` has no dependency field, so speckit tasks never show as blocked.
