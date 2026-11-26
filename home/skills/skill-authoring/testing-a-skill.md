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

    home/skills/skill-authoring/scripts/eval-triggers.sh [--min PERCENT] [--max-false-fire PERCENT] [SKILLS_DIR]

A `MISS` means the description does not separate that skill from the one it
routed to, so read both descriptions before editing either.

Near misses go in the same file as `not_fire`: phrases that sound like this
skill but belong to a sibling, such as "review this diff" for `git`:

    {"fire": ["commit this"], "not_fire": ["review this diff before I merge it"]}

A `not_fire` phrase passes when the router picks any skill but this one. A
`FALSE FIRE` line means it picked this one, so this description claims
vocabulary its sibling owns. Pair each `not_fire` list with the sibling's own
list pointing back, so both directions of the overlap are measured.

The two are scored apart. `top-1` counts `fire` phrases only, and `--min`
gates it. `false-fire` is the share of `not_fire` phrases routed to their own
skill, and `--max-false-fire` gates it. A combined figure would let easy near
misses hide a drop in fire accuracy.

## Behaviour evals: does the body change the outcome?

Same loop as `testing`'s TDD, applied to prose instead of code:

1. Run the scenario in a fresh session, skill unmodified. Confirm it fails
   the way the skill is meant to prevent.
2. Write the skill content that fixes it.
3. Re-run the same scenario in another fresh session. Confirm it now
   succeeds.

A skill written without watching it fail first is a guess dressed as a fix.

Keep the scenarios as cases so the loop can be re-run. Cases live in
`home/skill-evals/<skill>/<case>/`: a `prompt.md` (frontmatter plus the
prompt) and a `graders/` directory. That is the native `claude plugin eval`
format, which runs every case with and without the skill and reports the
delta.

- Pick a prompt the model gets wrong *without* the skill. A case both arms
  pass measures nothing.
- Prefer `regex` graders; use `llm` only for behaviour a pattern cannot see.
- Add a `tool_used: Skill` grader so a with-arm pass that never loaded the
  skill shows up.

`scripts/run-behaviour-evals.sh --check` validates every case offline (the
`skills-behaviour-evals` flake check runs it). The live run spends credit, so
it is opt-in and needs a logged-in `claude` CLI:
`scripts/run-behaviour-evals.sh [SKILL...] -- --runs 3`.
Each skill is capped at `$SKILL_EVALS_MAX_COST_USD` (default 1) unless
`--max-cost-usd` is passed.
It packs one skill per throwaway plugin, so each delta is that skill alone.

## Cost and usage audit

- `/doctor` (bundled) reports each skill's context cost and invocation
  frequency — run it after a change that could bloat a description or
  duplicate another skill's trigger vocabulary.
- `claude plugin eval` runs the behaviour-eval cases above; its exit code
  (0 pass, 1 below threshold, 2 partial) gates like a test suite.

## Related

Script-backed skills (e.g. `git`'s `scripts/`) verify with the language's
real test framework, not this — see `testing`.
