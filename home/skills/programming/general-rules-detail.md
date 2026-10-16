# General rules, in full

The one-line forms of these rules are in `SKILL.md`. This file holds the full
wording. Read the comment section before adding or editing any comment, and the
rest when a rule's one-liner leaves you unsure.

## Comments

- **Match the surrounding code — except comment density.** Naming style,
  error handling, and file layout come from the neighbours, not your
  defaults. A diff that reads like the rest of the file beats one that is
  independently prettier. Comment density is the exception: a file full of
  comment noise is not a convention to match. Do not add comments because the
  file already has many.
- **Default to no comments.** This overrides "match the surrounding code":
  an over-commented neighbour is never a reason to add more. Well-named
  identifiers already say what the code does; a comment restating that is
  noise. Write one only when the *why* is non-obvious — a hidden constraint,
  a subtle invariant, a workaround for a specific bug, behaviour that would
  surprise a reader — and drop it if its absence would not confuse a future
  reader. Never comment what the code does, reference the current task, fix,
  caller, or issue number (`used by X`, `added for the Y flow`, `handles the
  case from issue #123`), or leave a `// removed` marker for deleted code.
  Explaining *why* a workaround exists is fine; citing the ticket is not.
- **Comments earn their place, then get out of the way.** One short line,
  plain words, the constraint stated directly — no multi-line blocks, no
  second sentence restating the first. Same bar as the `writing` skill's
  dyslexia/ADHD baseline.

## Judgement rules

- **Don't program by coincidence.** If you cannot say *why* it works, it only
  happens to pass. Code arrived at by permuting until the test went green is
  the most expensive kind to own: the next person, including you, will assume
  it was reasoned. Understand the mechanism, or say plainly that you have not.
- **Name well; rename when needed.** A name that no longer describes the thing
  is a defect, not cosmetics: it misleads every later reader. Renaming the
  thing you are already changing is part of the change; renaming things you
  are not otherwise touching is scope creep.
- **Don't live with broken windows.** A known-wrong thing left in place
  licenses the next one, and the decay compounds. Fix it if in reach; if
  genuinely out of scope, record it where it will be found. Never step over
  it silently.
- **Treat reluctance as a signal.** Circling a change without starting it
  usually means the requirement is unclear or the design is wrong, not that
  the work is unpleasant. Re-read the requirement before pushing through.
