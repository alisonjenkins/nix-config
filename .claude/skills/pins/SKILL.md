---
name: pins
description: How this repo records, reviews and removes pins (flake inputs held at a rev or tag, insecure-package permits, overlay version overrides). Use when adding, changing or removing any pin, when a nightly flake.lock update breaks and holding something back looks tempting, when a weekly pins issue appears, or when asked why something is pinned.
paths:
  - "flake.nix"
  - "pins/**"
  - "overlays/default.nix"
  - "scripts/pins.py"
---

# Pins

A pin freezes something so a nightly lock update cannot move it: a flake input
at a rev or tag, a `permittedInsecurePackages` entry, an overlay that forces a
package version. Pins are debt. They stop security fixes and new features
arriving, and a pin whose reason is forgotten is never removed. So every pin is
registered, has a deadline, and is tested automatically for whether it can go.

Source of truth: `pins/registry.json`. Tool: `scripts/pins.py`. Rationale:
ADR 0051.

## The rule

**No pin without a registry entry.** `pins.py check` runs in pre-commit and in
the `flake-check` job and fails when:

- a rev- or tag-pinned flake input, or a `permittedInsecurePackages` name, has
  no entry;
- an entry's pin no longer exists in the code (remove the entry with the pin);
- an entry has no reason, no probe or `manual_test`, or a review deadline
  further out than its class allows.

A deadline that has passed does not fail PRs (an unrelated change must not be
blocked by an old deadline). The weekly workflow raises an issue instead.

## Adding a pin

First ask whether to pin at all. If a nightly bump broke something, find the
cause and say what you saw, not what you guess: the 2026-10-23 REA breakage
was first pinned as "Ghidra 12.1.3/12.1.4 regressed", which a bisect showed was
wrong (the nixpkgs rev was the cause). A pin recorded with the wrong reason
cannot be probed correctly.

Then add an entry to `pins/registry.json`:

| field | what goes in it |
|---|---|
| `id` | the flake input name, or a short slug for an overlay or permit |
| `class` | `workaround` (a bug to wait out, 45 days), `exception` (insecure permit, 90), `lockstep` (must match something else, 90), `tracked` (a deliberately chosen release, 180) |
| `kind` | `flake-input`, `insecure-package` or `overlay-override` |
| `site` | flake inputs: `{"input": "<name>"}` (nested nixpkgs: `<name>.inputs.nixpkgs`). Others: `{"file": ..., "match": "<exact text in that file>"}` |
| `since`, `reviewed`, `review_by` | ISO dates. `review_by` minus `reviewed` must not exceed the class limit |
| `reason` | what broke, observed, with versions or revs and a link. At least a full sentence |
| `removal` | the exact steps to delete the pin |
| `probe` or `manual_test` | how to tell it can go. Prefer a probe |

Put a short `# see pins/registry.json` comment at the site only if it helps a
reader; the registry, not the comment, is the record.

## Probes

A probe passes (exit 0 or true) when the condition holds. Types:

- `command`: any command, run from the repo root. For an input pin, build the
  thing that broke with `--override-input <input> github:nixos/nixpkgs/nixos-unstable`;
  passing means the pin is no longer needed. `meaning` is `removable` (default)
  or `update-available`.
- `issue-closed`: `{"repo": "NixOS/nixpkgs", "number": 571232}`.
- `version-at-least`: `{"flake_ref", "attr", "version"}` for "drop this
  override once nixpkgs reaches X".
- `newer-release`: `{"repo", "current"}` for tracked and lockstep pins (falls
  back to tags when a project publishes no GitHub releases).

A probe that errors reports `n/a`, never "removable". A pin with no probe needs
a `manual_test` that someone can actually run.

## Reviewing and removing

Every Monday `pins.yaml` runs all probes on the home runner and opens one issue
per pin that: can probably be removed, has an update, is overdue, is older than
180 days (`tracked` excepted), or is flagged `needs_triage`. It never opens a
duplicate of an open issue.

When an issue arrives, do one of:

1. **Remove it.** Follow `removal`, run the pre-commit hook, delete the entry in
   the same commit, build an affected host.
2. **Re-test and keep it.** Run the probe or `manual_test` yourself. Only then
   move `reviewed` to today and `review_by` forward, and write what you found in
   `review_note`. Moving the date without testing defeats the system.
3. **Fix the cause.** Report it upstream, add the link to `upstream`, and keep
   the pin until the probe passes.

Do not extend a `workaround` indefinitely: the 180-day stale issue exists to
force a decision, which is to fix, replace, or accept it as an `exception`
with a written risk.

## Commands

```
python3 scripts/pins.py check                # what CI runs
python3 scripts/pins.py report               # table of every pin and its status
python3 scripts/pins.py probe --id niks3     # run one probe (needs nix and gh)
python3 scripts/pins.py probe --dry-run      # show what would run
python3 scripts/pins.py issues --probe-json probe.json --repo owner/name --dry-run
python3 -m unittest discover -s scripts/tests -p test_pins.py
```

`PINS_TODAY=YYYY-MM-DD` overrides the date for repeatable runs.

## Traps

- `nixpkgs_rea_pin`-style pins are rev-pinned in the input URL, which is what
  stops `nix flake update` moving them. Pinning only in `flake.lock` does not
  survive the next update.
- An overlay pin is also a pin. If you add `version = "x"` to an overlay to get
  a newer package early, register it with a `version-at-least` probe so it
  removes itself from your attention when nixpkgs catches up.
- `permittedInsecurePackages` can appear in several files for one package.
  Register it once with the main file as `site`; the check treats a name as
  covered when any entry matches it.
- Do not use a bare `git stash` or edit `flake.lock` by hand to hold a pin
  steady.
