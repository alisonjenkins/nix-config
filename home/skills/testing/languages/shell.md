# Testing shell scripts

This repo's own skill scripts (`home/skills/*/scripts/*.sh`) are tested with
`bats`, driving the real script against fixture-driven fake CLIs rather than
mocking shell internals.

## bats

- One `.bats` file per script, in `scripts/tests/`, named after the script
  under test (`poll-pr-review.sh` → `poll-pr-review.bats`).
- `setup()` builds a `script_dir`, resolves `script` to the real script's
  path, and stages fakes through `stage_fakes_and_export_path "$script_dir"`
  (`load 'sandbox-path-helpers'`), which copies them with a shebang that
  resolves, instead of `export PATH="$script_dir:$PATH"`.
- `run bash "$script" args...` captures `$status` and `$output`; assert on both
  (`[ "$status" -eq 1 ]`, `[[ "$output" == *"usage:"* ]]`), not just exit
  code — the message is part of the contract for a script a human or agent
  reads.
- Any script a test generates and git or the script executes (for example a
  hook): write `'#!'"$(command -v bash)"` as its shebang.
- See `home/skills/git/scripts/tests/poll-pr-review.bats` and
  `home/skills/delegation/scripts/tests/delegate.bats` for the working
  pattern.

## Fixture CLI shims

A fixture is a same-named executable placed ahead of the real tool on
`PATH`, so the script under test cannot tell it from the real `gh`/`copilot`.
It reads its behaviour from files the test drops in a temp dir (e.g.
`FAKE_GH_FIXTURES`), not hardcoded output, so each test can set up a
different response without editing the shim.

- `home/skills/git/scripts/tests/gh` — fake `gh`, driven by
  `FAKE_GH_FIXTURES/*.tsv`/`*.txt` fixture files.
- `home/skills/delegation/scripts/tests/copilot` — fake `copilot` CLI.

Write a new shim the same way: a thin executable matching the real tool's
invocation shape, reading canned output from a fixture file the test controls,
never hitting the network. This is `testing`'s general mocking policy for
shell — mock only what you cannot run (a paid external API here), and mirror
the *interface*, not your own code's internal structure.

## Hand-rolled harness (no bats)

When a project can't add a `bats` dependency, a plain-bash harness works:
`home/skills/repo-audit/scripts/tests/harness.sh` defines `assert_eq`,
`assert_exit`, `assert_contains` and a pass/fail counter, sourced by each
`scripts/tests/*.test.sh` file; `run-all.sh` drives them all and reports a
summary. Prefer `bats` when available (clearer per-test output,
`run`/`$status`/`$output` capture); fall back to this only when it isn't.
