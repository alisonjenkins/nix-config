# Testing shell scripts

This repo's own skill scripts (`home/skills/*/scripts/*.sh`) are tested with
`bats`, driving the real script against fixture-driven fake CLIs rather than
mocking shell internals.

## bats

- One `.bats` file per script, in `scripts/tests/`, named after the script
  under test (`poll-pr-review.sh` → `poll-pr-review.bats`).
- `setup()` builds a `script_dir`, resolves `script` to the real script's
  path, and prepends a fixture-CLI directory to `PATH` so the script's calls
  to `gh`/`copilot`/etc. hit the fake, not the real network tool.
- `run "$script" args...` captures `$status` and `$output`; assert on both
  (`[ "$status" -eq 1 ]`, `[[ "$output" == *"usage:"* ]]`), not just exit
  code — the message is part of the contract for a script a human or agent
  reads.
- See `home/skills/git/scripts/tests/poll-pr-review.bats` and
  `home/skills/delegation/scripts/tests/delegate.bats` for the working
  pattern.

## Fixture CLI shims

A fixture is a same-named executable placed ahead of the real tool on
`PATH`, so the script under test cannot tell it isn't talking to the real
`gh`/`copilot`. It reads its behaviour from files the test drops in a temp
dir (e.g. `FAKE_GH_FIXTURES`), not from hardcoded output, so each test can
set up a different response without editing the shim.

- `home/skills/git/scripts/tests/gh` — fake `gh`, driven by
  `FAKE_GH_FIXTURES/*.tsv`/`*.txt` fixture files.
- `home/skills/delegation/scripts/tests/copilot` — fake `copilot` CLI.

Write a new shim the same way: a thin executable script matching the real
tool's invocation shape, reading canned output from a fixture file the test
controls, never hitting the network. This is the shell-script equivalent of
`testing`'s general mocking policy — mock only what you cannot run (a paid
external API here), and mirror the *interface*, not your own code's
internal structure.

## Hand-rolled harness (no bats)

When a project can't add a `bats` dependency, a plain-bash harness works:
`home/skills/repo-audit/scripts/tests/harness.sh` defines `assert_eq`,
`assert_exit`, `assert_contains` and a pass/fail counter, sourced by each
`scripts/tests/*.test.sh` file; `run-all.sh` drives them all and reports a
summary. Prefer `bats` when it's available — clearer per-test output and
`run`/`$status`/`$output` capture — and fall back to this pattern only when
it isn't.
