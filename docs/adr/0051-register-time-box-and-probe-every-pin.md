# 0051. Register, time-box and probe every pin

- Status: Accepted
- Date: 2026-10-23

## Context

The repo has accumulated pins: ten flake inputs held at a rev or tag, five
`permittedInsecurePackages` entries, and overlays that force a package version.
Some carry a good comment, some none, and about 150 lines mention pinning. Nobody
could say which were still needed. Three examples found on 2026-10-23:

- `nixpkgs_lqx_pin` has held a kernel since 2026-01-01 "until amdgpu bugs are
  fixed", with no record of which bugs.
- `nixcord` is pinned to a rev, yet its own commit (e994700d) is titled "unpin
  nixcord, was fixed a year ago".
- The `ghidra-bin` 12.1.2 overlay pin (6bc8f29c, two days old) recorded a cause
  ("12.1.3/12.1.4 binaries regressed") that a bisect later disproved: the
  nixpkgs rev was the cause, so the pin did not fix the next breakage and had to
  be removed. Three more version overrides were already obsolete because
  nixpkgs had caught up, and nothing said so.

A pin stops security fixes and new features arriving. The cost grows silently,
and the reason is the first thing forgotten.

## Decision

Every pin is an entry in `pins/registry.json` with a reason, the date it was
added, the date it was last reviewed, a review deadline, and a probe or a manual
test. `scripts/pins.py` enforces and reports on it:

- `check` (pre-commit and the `flake-check` job) fails if a pin exists in the
  code without an entry, an entry's pin has gone, or a deadline is further from
  the last review than the pin's class allows (workaround 45 days, exception 90,
  lockstep 90, tracked 180). Overdue deadlines warn only, so an unrelated PR is
  never blocked.
- `probe` tests whether each pin can go. For a flake input it builds the thing
  that broke with `--override-input <pin> <upstream>`. Other probes check a
  closed upstream issue, a nixpkgs version reaching an override's version, or a
  newer release for a tracked pin. A failing probe reports "n/a", never
  "removable".
- A weekly workflow runs the probes and opens one issue per pin that is
  removable, has an update, is overdue, is older than 180 days, or is flagged as
  having no known reason. It never duplicates an open issue.

Review dates only move forward after a re-test, with the finding written down.
A `workaround` cannot be extended forever: past 180 days it is raised weekly
until someone fixes the cause or accepts it explicitly as an `exception`.

Why a time limit rather than "pin until it works": a probe can only be written
for failures that can be reproduced, and some pins (a kernel hardware bug) cannot
be. The deadline guarantees a human looks regardless.

## Alternatives rejected

- **Comments at the pin site only.** That is the status quo. Nothing finds a
  stale comment, and nothing is raised when its condition is met.
- **Renovate for the pins.** Renovate bumps versions, but these pins exist to
  hold a version back. It cannot test whether the original problem is gone.
- **Fail CI on overdue pins.** Rejected: one forgotten deadline would block every
  unrelated PR and the nightly lock update, which is the failure this record
  came from.
- **Auto-remove pins whose probe passes.** Rejected: removal changes what runs
  on real machines. The probe proves the build passes, not that the host
  behaves; a person reviews the removal.

## Consequences

- Adding a pin now costs a registry entry. That is the point.
- 15 pins were registered on day one, two of them already past 180 days and
  three flagged as having no recorded reason.
- Probes run on the home builder every Monday and build the REA check, so they
  use runner time. They are schedule-only, so fork PRs never reach them.
- Probe quality varies. Kernel and hardware pins stay `manual_test`, and the
  deadline is the only control on them.

## Evidence

- First `pins.py probe` run on 2026-10-23: the `claude-code`, Copilot CLI and
  `linux-firmware` overlay overrides are all satisfied by current nixpkgs
  (2.1.308, 1.0.98 and 20261019 against 2.1.293, 1.0.93 and 20260514), the
  cachyos nixpkgs hold's upstream issue NixOS/nixpkgs#571232 is closed, and
  `niks3` is pinned at v1.7.0 while v1.15.0 exists.
- The nightly `flake.lock` PRs failed from 2026-10-17 to 2026-10-23 on two
  pin-shaped problems (see the PR that introduced `nixpkgs_rea_pin`).

## Revisit when

Pins are routinely extended without re-testing (look at `review_note` in the
history), or the weekly issues are ignored for a month. Then the system is
producing noise, and the answer is fewer pins, not looser deadlines.
