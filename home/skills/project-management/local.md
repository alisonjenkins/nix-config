# Local backend

Selected with `-b l -d <dir>`. Tasks live in `<dir>/tasks.md`; no account or network is needed. The directory can be anywhere, including outside a repository.

## Format

The same line format speckit uses, so a speckit feature directory works as `-d` unchanged:

```
- [ ] T001 [P] [US1] Description owner:ali deps:T002,T003 due:2026-11-01T00:00:00Z est:30 prio:2
- [X] pm:launch-checklist Draft the launch checklist
```

- `[ ]` is open, `[X]` is done. `update --state` flips it.
- The id is `T<digits>` or `pm:<slug>`. Lines without one are ignored.
- `[P]` and `[US#]` markers are skipped when reading titles.
- Optional fields anywhere after the id: `owner:`, `deps:`, `due:`, `est:`, `prio:`.

## What it cannot do

- `--label`, `--milestone`, `--comment` and `--unlabel` are not supported and fail with a clear error.
- `stale` is always `n/a` because the file has no timestamps.
- `sync-plan` copies missing task lines from the plan file into `tasks.md` (and creates the file). It has no epic or per-task mode.

## Using it for project docs

Keep `charter.md`, `plan.md` and `status.md` next to `tasks.md` in the same directory so the whole project is one folder.
