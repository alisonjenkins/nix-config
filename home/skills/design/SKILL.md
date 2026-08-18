---
name: design
description: Use when deciding how to structure a change — where a responsibility belongs, whether to add a parameter or a new function, whether to reach for inheritance or composition, how to split a module that does two things, or when a change is touching far more files than its size suggests it should. Also for reviewing the shape of an existing design, untangling coupling, and deciding what to make configurable. Covers coupling, cohesion, orthogonality, global and shared state, inheritance vs delegation, and keeping decisions reversible.
---

# Design

`programming` covers how to write the change. This covers what shape the change
should be.

## The test

**Is what you are leaving behind easier to change than what you found?**

That is the whole criterion. Not shorter, not cleverer, not more general —
easier to change. Every rule below is a way of getting there, and where a rule
conflicts with that criterion in a specific case, the criterion wins.

Two questions make it concrete:

- If the requirement that drove this code changed tomorrow, how many files
  would I open?
- Can I describe what this module is responsible for in one sentence, without
  the word "and"?

## Orthogonality

Unrelated things should not affect each other. A change to the database schema
should not touch the HTTP layer; a change to the log format should not touch
business logic.

The diagnostic is cheap and you already have it: **if a small change touches
many files, the design is coupled, not the change big.** When you notice that,
say so — do not silently absorb the cost and move on. Fixing it may be out of
scope, but noticing it out loud is never out of scope.

Cohesion is the same property from the inside: things that change together
live together. A module whose parts change on unrelated schedules should be
two modules.

## Where the decision usually goes wrong

- **Generalising on the first use.** Write the concrete thing. The right
  abstraction is visible on the second or third use and invisible on the first.
- **Adding a flag instead of a seam.** A boolean parameter that switches
  behaviour is two functions wearing a trench coat. Name them.
- **Putting the logic where the data is convenient** rather than where the
  responsibility is. Convenience now, coupling forever.
- **Deciding something irreversibly to save an hour.** See
  [reversibility.md](reversibility.md).

## Routing

| Question | Read |
|---|---|
| Who should call whom; inheritance vs composition; a chain of accessors | [coupling.md](coupling.md) |
| Where state lives, globals, shared mutable data, transforming data | [data-and-state.md](data-and-state.md) |
| Locking in a decision, config vs hardcoded, prototypes and tracer bullets | [reversibility.md](reversibility.md) |

## Related

- Before any of this, if the requirement is not settled: the `requirements`
  skill. A design cannot be judged easier-to-change without knowing what is
  expected to change.
- Writing the code once the shape is settled: the `programming` skill.
- Testability is a design signal, not a testing afterthought — a thing that is
  hard to test is usually coupled. The `testing` skill covers what to do about
  it.
- Judging someone else's shape: the `review` skill.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt) — tips 14, 17-19, 44-55. Full tip list: https://pragprog.com/tips/
