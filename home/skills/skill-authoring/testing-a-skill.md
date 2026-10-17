# Testing a skill

## Trigger evals: does the description fire?

Keep a short should-fire / should-not-fire phrase list next to the SKILL.md:
a few real phrasings a user would type, plus near-misses that belong to a
neighbouring skill. Re-check it in a fresh session whenever the description
changes — a rewrite that reads better to you can still stop matching the
phrasing users actually use.

### eval-triggers.sh

`eval-triggers.sh` measures whether a model would actually route each trigger
phrase to the right skill, judged from the descriptions alone. It is opt-in and
spends Gemini quota (one call for all phrases, via the delegation skill's
`delegate-to-gemini.sh`):

    home/skills/skill-authoring/scripts/eval-triggers.sh [--min PERCENT] [SKILLS_DIR]

A `MISS` means the description does not separate that skill from the one it
routed to, so read both descriptions before editing either.

## Behaviour evals: does the body change the outcome?

Same loop as `testing`'s TDD, applied to prose instead of code:

1. Run the scenario in a fresh session, skill unmodified. Confirm it fails
   the way the skill is meant to prevent.
2. Write the skill content that fixes it.
3. Re-run the same scenario in another fresh session. Confirm it now
   succeeds.

A skill written without watching it fail first is a guess dressed as a fix.

## Cost and usage audit

- `/doctor` (bundled) reports each skill's context cost and invocation
  frequency — run it after a change that could bloat a description or
  duplicate another skill's trigger vocabulary.
- `claude plugin eval` runs a plugin-packaged skill's `evals.json` in CI,
  gateable like a test suite.

## Related

Script-backed skills (e.g. `git`'s `scripts/`) verify with the language's
real test framework, not this — see `testing`.
