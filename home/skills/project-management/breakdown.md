# Breaking a project down

Turn one project into epics, then tasks small enough to finish in a day. Write the result as a plan file the tracker can ingest.

## Steps

1. **Restate the project in one sentence:** what is wrong today, and for whom. If you cannot, ask before breaking anything down.
2. **Define done.** Two to five outcomes someone could check. These become the epics' acceptance lines.
3. **Cut epics.** At most seven. Each ships something on its own. A code feature that needs a spec is one epic, and it hands off to `/speckit-specify`; do not copy its content here.
4. **Cut tasks** under each epic.
   - Start with a verb. One deliverable each.
   - Aim for 15 to 240 minutes. A task over a day is an epic.
   - Add `est:<minutes>`. Leave it off rather than guess wildly; unestimated tasks are visible in `list`.
   - Add `deps:T001,T002` only for real ordering. Do not chain tasks for neatness.
   - Add `prio:<n>` (1 highest) and `due:<ISO8601 UTC>` only where they differ from the epic.
   - Give each an acceptance line in the plan prose, not in the task line.
5. **Order and check.** Walk the dependency chain. The critical path should be the shortest list you can read aloud. Flag the riskiest task and do it early.
6. **Write it down.** Task lines use the tracker format, so `pm sync-plan` can ingest them:

```
- [ ] T001 [P] Set up the repo est:30 prio:1
- [ ] T002 Write the schema deps:T001 est:90
- [ ] pm:launch-checklist Draft the launch checklist est:60
```

Use `Tnnn` ids inside a speckit feature and `pm:<slug>` for plain plan items. `[P]` marks a task that can run in parallel.

## Sizing guide

| Estimate | Meaning |
|---|---|
| 15 to 60 min | one focused change |
| 60 to 240 min | a task; split if it has two verbs |
| over 240 min | an epic; cut further |

## Red flags

- A task whose title has "and" in it.
- An epic with no outcome you could check.
- Every task depending on the previous one.
- No estimate on the riskiest task.

## Hand-off

Show the user the plan before creating tickets. Then `pm sync-plan <file>` (dry run), then `--apply` once they agree.
