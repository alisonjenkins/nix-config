# 0065. Skill behaviour evals with `claude plugin eval`, one plugin per skill

- Status: Accepted, live baseline pending
- Date: 2026-11-26

## Context

The skills had trigger tests (does the description route to the skill) but
nothing that checked whether a skill's body changes what the model does.
`testing-a-skill.md` described a manual fail-then-pass loop that nobody
re-ran, so a regression in a prose skill was invisible.

Claude Code ships `claude plugin eval`. It runs each case in a sandbox with
the plugin and without it, grades both arms, and reports the delta. The
skills here are not packaged as a plugin; they deploy from `home/skills` to
`~/.claude/skills`.

## Decision

- Cases live in `home/skill-evals/<skill>/<case>/` in the native format
  (`prompt.md` plus `graders/*.md`). The first set covers the three most-used
  prose skills: programming, debugging and infra.
- `run-behaviour-evals.sh` builds one throwaway plugin per skill (the skill
  plus its cases, copied, not symlinked) and runs `claude plugin eval` on it.
  One skill per plugin means each delta measures that skill alone.
- Each case is chosen so the without arm is expected to fail. Graders are
  regexes where a pattern can see the behaviour, `llm` where it cannot, and
  every case has a `tool_used: Skill` grader to show the skill fired.
- `--check` validates every case offline. The `skills-behaviour-evals` flake
  check runs it and the runner's bats tests, so a malformed case fails CI
  without spending credit.
- The live run is opt-in, defaults to Haiku, and is capped with
  `--max-cost-usd`.

## Things that are not obvious

- **The without arm is bare.** It loads no plugin, user settings, CLAUDE.md or
  other skills. The delta is "this skill against nothing", not "against the
  usual setup".
- **The with arm relies on the skill firing on its own.** A low delta can mean
  the body does nothing, or that the description did not fire. The `Skill`
  grader separates the two.
- **Unknown `prompt.md` keys are errors** in the eval runner, which is why
  `--check` rejects them rather than warning.
- **The live run needs a logged-in CLI.** A session using desktop host auth
  reports `Not logged in` (`partialReason: auth_failed`, exit 2). Run
  `claude /login` in a terminal first. The baseline numbers are not recorded
  yet for this reason.
