# 0001. A ci skill for pipeline design, and /ci-audit to apply it

- Status: Accepted
- Date: 2026-11-26

## Context

CI knowledge was spread across three places, none of them about pipeline
design:

- `testing` says how to write tests and fix one flaky test's code.
- `repo-audit`'s `ci-pipeline.md` checks repo hygiene: workflow permissions,
  a caching step being present, required checks matching jobs.
- Repo ADRs 0043 (shared sccache), 0044 (parallel PR check) and 0062 (scope
  the PR check by diff) hold hard-won lessons, but only for this repo.

Nothing told an agent how tests should run in CI, how to keep checks free of
flakes, how to key a cache, or how to skip work safely. Agents setting up CI
in a new repo had to rediscover each rule.

## Decision

1. Add a `ci` skill family: `SKILL.md` with the rules that hold everywhere,
   and four topic files: `running-tests.md`, `reliability.md`, `caching.md`,
   `scoping.md`.
2. Write the repo ADR lessons generically. Examples: unknown paths run
   everything; the gate's own script changing forces a full run; process
   group cancel; a missing result marker counts as failure; never make a
   local clone shallow.
3. Incremental mutation testing in `scoping.md`: reach a clean baseline once,
   then mutate only the diff per PR (`cargo mutants --in-diff`, StrykerJS
   `--incremental`), with a scheduled full run as the backstop. Tool flags
   were checked against upstream docs; gremlins' diff option is not
   documented, so the skill tells the agent to check `--help` instead of
   naming a flag.
4. Link to `testing` for per-language tool setup instead of duplicating it.
5. Add `/ci-audit`, a separate typed-only skill (`user-invocable-only` in
   `skillOverrides`, like `docs-audit`). It reuses `repo-audit`'s
   `ci-pipeline` and `branch-protection` checks for the mechanical part,
   then checks each `ci` topic file by reading the workflows and run
   history. It proposes fixes as diffs and applies none without a yes.

## Alternatives rejected

- **Extend `repo-audit/ci-pipeline.md`.** That file is a hygiene check with a
  script behind it. Design guidance is read when building CI, not only when
  auditing, and would bloat the audit's routing.
- **Put CI rules in `testing`.** `testing` is already the largest family and
  is about test code. Caching, path gating and runner reliability are not.
- **A `.claude/commands/ci-audit.md` slash command.** Commands do not reach
  the other agent CLIs (agy, opencode) that share `home/skills/`. A typed-only
  skill does.
- **A model-invocable `ci-audit`.** Its triggers would overlap `ci` and
  `repo-audit`. The user asked for a command; hiding it from the model's
  listing avoids the overlap.

## Evidence

- Repo ADRs 0043, 0044 and 0062 for the scoping, parallelism and cache
  rules.
- Flake triage in other repos: the same check had failed on the default
  branch before the suspect change; "Connection reset by peer" and disk-full
  failures were infrastructure, not tests.
- cargo-mutants `--in-diff` and `--iterate`: <https://mutants.rs/in-diff.html>.
- StrykerJS incremental mode: <https://stryker-mutator.io/docs/stryker-js/incremental/>.

## Revisit when

- Behaviour evals for skills land: add evals that check an agent following
  `ci` adds an aggregator check and refuses blanket retries.
- A second forge (GitLab, Forgejo) is in real use: add its specifics to the
  topic files.
- gremlins documents its diff option: name it in `scoping.md`.
