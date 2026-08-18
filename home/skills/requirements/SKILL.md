---
name: requirements
description: Use before starting work when the request names a solution rather than a problem ("add caching", "make it faster", "clean this up", "refactor this", "it should just work"), when a term in it could mean two things, when you are about to guess which reading was meant, or when you cannot say in one sentence what goes wrong today and for whom. Also when a constraint looks like it makes the task impossible. Covers separating the problem from the proposed solution, marking constraints as given versus assumed, deciding which assumption to state and proceed on versus which question actually blocks, and keeping terms consistent.
---

# Requirements

## If you got here and the ask was clear

Say so in one line and carry on. This skill is invoked on a cheap check, so it
will sometimes fire on a request that was fine — that is the intended cost.
Do **not** manufacture a clarifying question to justify having read it. An
unnecessary question costs the user a round trip; an unnecessary read costs
nothing.

## Nobody knows exactly what they want

Not because they are careless — because wanting something precise requires
seeing something concrete first. A request is the start of a feedback loop, not
a specification. Expect the real requirement to become visible once there is
something to react to, and design the first cut to be cheap to react against.

This does not license guessing. It licenses producing something concrete
quickly and saying plainly what you assumed.

## Separate the problem from the solution

Most requests arrive pre-solved. "Add a cache" is a solution; the requirement
underneath is "the page takes four seconds". Find the requirement, because:

- the proposed solution may not address it (the four seconds may be one slow
  query, not repeated work);
- the requirement is stable and the solution is not — it survives the next
  three refactors;
- solving the stated solution instead of the stated problem is the most common
  way to deliver something correct and useless.

Ask "what goes wrong today, for whom?" If you can answer that, you have the
requirement. If you cannot, you are implementing a guess.

**This is not permission to substitute your own idea for theirs.** When the
user names a solution and it does address the problem, build what they asked
for. Raise the mismatch in a sentence, then proceed with their decision if they
reaffirm it.

## Ask or assume?

The default is **assume, state, proceed** — this is a working mandate, not a
style preference. Blocking on a question costs the user a round trip and
usually delivers nothing.

Block only when proceeding under any assumption would be unsafe, destructive,
or would make the whole deliverable useless if wrong. Everything else:

1. Do all the work that does not depend on the answer.
2. For the part that does, pick the reading a careful colleague would pick.
3. State the assumption where the user will see it, in one line.

When you do have to ask, ask about the *problem*, not the implementation.
"Should this apply to archived records too?" is answerable; "should I use a
hash map or a btree?" is your job.

## Constraints are usually assumed, not real

When something looks impossible, the blocking constraint is often one you
imported rather than one that was stated. List the constraints explicitly and
mark each as *given* or *assumed*. The assumed ones are where the solution is.

Ask of each: is this actually required, and what does it cost to relax? The
answer is frequently "nothing, nobody ever needed that".

## Policy is metadata

Write down the rule, not today's answer to the rule. "Only admins may delete"
is a requirement; `if user.id == 1` is a hardcoded snapshot of it that will be
wrong the first time the org chart changes. Where the rule can be expressed as
data or configuration, express it there — see the `design` skill's
`reversibility.md`.

## Keep the words stable

Use the project's own vocabulary and use one term per concept. If the codebase
says *tenant*, do not introduce *customer* for the same thing in a new module,
a comment, or a commit message. Where a term is genuinely ambiguous in the
project, pin it once — in the module doc or the repo's own docs — and then use
it consistently rather than re-explaining it at each site.

## Related

- The interactive discovery loop, when the user wants to explore the shape of a
  feature together before any code: `superpowers:brainstorming`. This skill
  covers judging and sharpening a request that has already arrived; that one
  covers eliciting one that has not.
- Turning the settled requirement into a structure: the `design` skill.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt) — tips 75-81. Full tip list: https://pragprog.com/tips/
