# Project documents

Four short documents cover a project. Put the conclusion first in each. Lessons that should outlive the project go to `docs/adr/` in the same change.

## Charter

```markdown
# <Project>: charter

**Problem.** One sentence: what is wrong today, and for whom.
**Outcome.** What is true when this is done, checkable.
**Scope.** In: ... Out: ...
**People.** Owner, reviewers, who is told.
**Constraints.** Deadline, budget, tools, rules.
**Risks.** Top three, each with a first mitigation.
**Done when.** The acceptance list.
```

## Plan

```markdown
# <Project>: plan

**Tracker.** Backend and location, for example `pm -b g -r owner/name`.
**Epics.** One line each, with the speckit feature path if there is one.
**Task list.** Task lines in the pm format (see breakdown.md).
**Order.** The critical path in one sentence.
**Dates.** Milestones with ISO8601 UTC dates.
```

## Status report

```markdown
# <Project>: status, <ISO8601 UTC date>

**State.** On track, at risk, or blocked, and why in one sentence.
**Counts.** Paste the `pm status` line.
**Done since last report.** Three bullets at most.
**Next.** The `next` task and the next milestone.
**Blocked.** Each blocker, who can unblock it, since when.
**Asks.** Decisions needed from the reader.
```

Generate the numbers with `pm status`; do not retype them.

## Retro

```markdown
# <Project>: retro

**What happened.** Three sentences.
**What worked.** Keep doing.
**What did not.** Each with the cause, flat, no blame.
**Changes.** Each with an owner. Durable ones become an ADR or a skill edit.
```
