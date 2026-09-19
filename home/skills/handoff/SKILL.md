---
name: handoff
description: Use when ending a session with work still open, before a context compaction, switching machines mid-task, or asked to write up state for another agent or session to continue from ("hand this off", "write up where we're at", "pick this up later"). Produces a structured summary: what was asked, what's done, what's in flight, decisions and why, open questions, and the exact next command.
---

# Handoff

## When

End of session with unfinished work, context about to compact, switching
machines, or handing a task to another agent or session.

## What to write

1. **Ask**: the original request, one line.
2. **Done**: what's actually finished and verified — not attempted.
3. **In flight**: what's mid-step, and its exact state (branch, PR number,
   last command run, its result).
4. **Decisions and why**: anything chosen between alternatives, so the next
   session doesn't re-litigate it.
5. **Open questions**: anything blocked on the user, unanswered.
6. **Next command**: the literal next thing to run, not "continue the work."

## Where it goes

Not memory — memory holds cross-session facts about the user or project, not
one task's transient state. Not a new file in the repo unless asked. A
message to the user, a PR/issue comment if the work is tracked there, or
whatever artifact the caller of this skill specifies.

## Related

- `consulting/brief.md`: same shape, different audience — a brief primes a
  fresh model to solve a problem it's never seen; a handoff primes a fresh
  session to resume one already in progress.
- `process-todo`: a standing local todo/done file, not a one-time handoff.
