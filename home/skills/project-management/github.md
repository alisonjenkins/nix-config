# GitHub backend

Selected with `-b g -r owner/name`. Uses the `gh` CLI, which must be authenticated (`gh auth status`). Issues must be enabled on the repository.

## How fields map

| Column | Source |
|---|---|
| `id` | issue number |
| `state` | `open` for open issues, `done` for closed |
| `owner` | first assignee |
| `deps` | a body line `deps: #12, #14` (stored as `12,14`) |
| `due` | milestone due date |
| `est` | label `est:<minutes>` |
| `prio` | label `prio:<n>` |

`stale` in `status` counts open issues untouched for 14 days.

## Epics

`sync-plan` writes one issue per tasks file, labelled `pm-epic`, with a hidden `<!-- marker -->` as its first line and a task list below it. The marker, not the title, is how the next run finds it, so do not delete the first line; epics are looked up by the `pm-epic` label, so do not remove that label either, or the next `--apply` creates a second epic. For a numbered spec directory the marker is `pm:spec-NNN` and the title `[spec-NNN] name`. Anywhere else the marker is `pm:plan-<repo-relative path of the file, lowercased, with / and _ turned into ->` (for example `pm:plan-docs-projects-foo-plan`) and the title is `[plan] <repo-relative path>`, so two projects never share an epic. Two epics with one marker are reported as `drift` and left alone.

Per-task issues (`--per-task ids|all`) are titled `Tnnn: description`. An issue belongs to a tasks file when its body has `Source: <path>` for that file or its title is exactly `Tnnn: description`, so `T001` in one spec never touches `T001` in another. An issue that starts with the id but is tied to neither is reported as `drift` (ambiguous) and left alone.

## Limits

- Reads fetch at most 200 issues (500 for the per-task lookup) by default and a truncation warning goes to stderr. `--max <n|all>` (before the verb, like `-r`) raises the cap for every lookup; `gh` pages through the API itself, so a larger cap costs more requests and nothing else. `all` means 100000. `sync-plan --apply` still refuses when a lookup hits the cap, because an issue missing from a truncated list would be created twice; rerun it with a larger `--max`. With `--label`, `--milestone` or `--assignee`, `gh` uses GitHub search, which returns at most 1000 issues whatever `--max` says.
- `list --limit <n> [--offset <m>]` pages the output rows (both backends), so a large repository does not flood the context. When rows remain, the last line is `# more=<rows left> next-offset=<m>`; pass that offset to get the next page.
- Projects v2 fields are not read yet (tracked in PENDING.md).
- `drift` lines mean the issue and `tasks.md` disagree. Nothing is changed; ask the user.

## Failure modes

- `gh: command not found` or `required tool not found: gh`: install it, or use the local backend.
- A 404 from gh on a private repository usually means the token lacks access, not that the repository is missing.
- `issues disabled`: enable Issues in repository settings, or track locally.
