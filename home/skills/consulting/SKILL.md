---
name: consulting
description: Use when you are about to make a third attempt at the same failure, when two hypotheses are disproved and you have no third, when a decision picks a dependency, data format or module boundary that will be hard to undo, when you have read the same file three times without the picture resolving, or when the user has told you twice that the same thing is still broken. Covers when to escalate to a stronger model, how to write a brief for one that cannot see this conversation, what to do when the escalation fails, and what not to escalate.
---

# Consulting a stronger model

This session runs on a fast model. Hard problems are handled by consulting a
stronger one and acting on what it says, not by grinding.

## When to consult

Escalate when **any** of these holds. They are countable on purpose: a model
that is stuck is the worst judge of whether it is stuck, so do not wait to feel
out of ideas.

- **Third attempt at the same failure**, where the first two changed something
  real and the symptom is unchanged.
- **Two hypotheses disproved and no third to hand.** Not two guesses: two
  hypotheses you actually tested.
- **A decision that is hard to undo**: picking a dependency, a data format, a
  schema, a module boundary, or anything whose blast radius is more than a
  handful of files.
- **The same file read three or more times** in one task without the picture
  resolving. Re-reading is what looks like progress while making none.
- **The user has said the same thing is still broken twice.** Their second
  report is the trigger; do not wait for a third.

Also consult when the cost of being wrong is high and the work is
irreversible: a migration, a destructive operation, anything touching live
infrastructure, even on the first attempt.

## When not to consult

- **Mechanical work.** Volume is not difficulty. A hundred repetitive edits are
  a job for this session or a cheap subagent, not for a consultant.
- **Anything the user has already decided.** Their decision is the input, not
  the question. Consulting to get a second opinion on it wastes the consult and
  ignores them.
- **Anything answerable by reading a file you have not read yet.** Reading is
  cheaper than consulting by a wide margin. Read first, every time.
- **Reassurance.** "I think this is right but I would like it confirmed" is not
  a trigger. Verify it instead: run the test, check the output.

Consulting is not free: the consultant reloads the whole memory hierarchy on
every spawn. Two unnecessary consults cost more than the session saved by
running on a fast model in the first place.

## Writing the brief

The consultant sees **none of this conversation**. Everything it knows comes
from what you write, and a thin brief produces a confident wrong answer. The
format is in [brief.md](brief.md). Use it every time; it takes a minute and it
is the whole difference between a useful consult and a wasted one.

## When a consult fails or comes back empty

Usually an exhausted usage quota or an unavailable model. Do not retry the same
tier in a loop.

1. Re-run the **same brief** one tier down, or handle it yourself if there is no
   tier below.
2. **Say so in your reply.** "The stronger consult was unavailable; this is my
   own conclusion" is honest and actionable. Reporting a decision as though a
   stronger model had confirmed it is not.

## Acting on the answer

- The consultant returns a decision, not code. Implementing it is your job.
- **It may tell you the question was wrong**: that you were debugging the wrong
  layer, or solving a problem the user does not have. That is the most valuable
  kind of answer. Take it, do not argue past it.
- **Do not accept it blindly either.** It worked from your brief, and your brief
  was incomplete. If its answer contradicts something you actually observed, say
  so and check which of you is wrong rather than picking by rank.
- Tell the user you consulted, and what came back. It changes what happens next
  and they should not have to infer it.

## Related

- `superpowers:systematic-debugging` and the `debugging` skill for the method
  that should have run *before* the third attempt. Most consults are avoidable
  by probing the right layer the first time.
- The `requirements` skill when the reason you are stuck is that the ask was
  never clear. Consulting will not fix an unclear requirement.
