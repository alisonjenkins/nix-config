---
name: debugging
description: Use when something is broken, failing intermittently, behaving differently in one environment than another, or when every check you run says it is fine but it plainly is not. Carries the method — reproduce, probe the layer closest to the fault, use a positive control, diff the working path against the failing one — and routes to the signals that commonly lie, how to pick the right layer to measure, and how to verify a fix actually took effect.
---

# Debugging

Use `superpowers:systematic-debugging` for the overall discipline — reproduce
first, form a hypothesis, change one thing. This family covers the part that
discipline does not: **which evidence to trust.**

## The method

1. **Reproduce it deliberately** before theorising. A bug you cannot summon on
   demand cannot be confirmed fixed either.
2. **Probe the layer closest to the fault.** Every layer above the broken one
   can report health — caches, health checks, connection state and summary
   metrics are all one step removed from the thing that is actually wrong.
3. **Run a positive control.** Before concluding "X does not work", prove your
   test method can detect X working at all. Otherwise you are debugging your
   own harness.
4. **Diff the working path against the failing one.** If the same operation
   succeeds one way and fails another, that asymmetry *is* the finding. Do not
   declare the component broken when a sibling path proves it is not.
5. **Change one thing, and confirm it took effect** — not that the symptom went
   away, which has many causes.

## The habit that catches the most

Ask: *what would this look like if the thing I trust were lying?* Then go and
check that thing directly. Most long debugging sessions are spent re-verifying
layers that were never broken, because the first green signal was believed.

## Routing

| Situation | Read |
|---|---|
| Everything reports healthy but the system is not | [false-signals.md](false-signals.md) |
| Deciding where to measure, in a stack or across a boundary | [layers.md](layers.md) |
| Confirming a fix actually applied, before claiming it works | [verifying-a-fix.md](verifying-a-fix.md) |

## Related

- Writing the fix once you understand it: the `programming` skill.
- Pinning the behaviour so it cannot regress: the `testing` skill.
- Infrastructure and cluster-specific failure modes: the `infra` skill.
