# 0066. Incremental mutation testing for skill scripts

- Status: Accepted
- Date: 2026-11-26

## Context

The skills ship about 65 shell scripts under `home/skills/*/scripts/`, most
with bats or plain-bash tests. A green suite showed the tests ran, not that
they would catch a broken script. The testing skill already asked for manual
saboteurs, which nobody re-ran.

Off-the-shelf mutation tools target compiled languages. None handles bash
with bats well, and a full mutation pass over every script on every change
would be slow.

## Decision

- `skill-authoring/scripts/mutate-scripts.sh` mutates one operator at a time
  in a temporary copy of `home/skills` and runs the script's tests. A mutant
  no test kills is a survivor.
- Script-to-test pairing is by name (`tests/<name>.bats` or `.test.sh`),
  else `skill-authoring/mutation/map.json`. An unpaired script is an error,
  so a new script cannot skip the check silently. Scripts with no tests yet
  are listed under `exclude` with that reason, as a visible to-do.
- Results go in `skill-authoring/mutation/baseline.json`, keyed on a hash
  of the script **and** its tests. A pair re-runs only when that hash
  changes or it still has open survivors.
- Equivalent mutants are accepted in `map.json` with a reason, keyed on the
  line's content hash, not its number, so unrelated edits do not reopen them.
- The `skills-mutation` flake check runs `--check`, which fails only on a
  stale or unpaired entry. It does not run mutants, so CI stays fast.

## Things that are not obvious

- **The script is part of the key, not only the tests.** A script change can
  add a branch no test covers, so editing a script re-runs its pair even
  when its tests are untouched.
- **Survivors do not fail CI.** The first baseline records the existing
  survivors; killing them is follow-up work per skill. `--check` only
  enforces that the recorded result matches the current files.
- **A timeout counts as killed.** A mutant that makes a loop spin is
  observable, and waiting longer would only slow the run.
