<!--
Sync Impact Report
- Version change: 1.0.0 → 1.0.1
- Modified principles: VII. Fork Patches Are Generated — clarified for a fork built as a
  flake input (niri now is); scope line updated to match
- Earlier: template (unversioned) → 1.0.0, all placeholders replaced (first ratification)
- Added principles: I. Atomic, Revertable History; II. Test First, Evidence Before Done;
  III. Infrastructure as Code, Live Changes by Consent; IV. Errors Carry Context;
  V. Right Altitude, Single Source of Truth; VI. Record the Why; VII. Fork Patches Are Generated
- Added sections: Operational Constraints; Development Workflow & Quality Gates; Governance
- Removed sections: none
- Templates:
  ✅ .specify/templates/plan-template.md — "Constitution Check" reads gates from this file; no edit needed
  ✅ .specify/templates/spec-template.md — no mandatory-section changes required
  ✅ .specify/templates/tasks-template.md — test-first ordering already supported; no edit needed
  ✅ .claude/skills/speckit-*/SKILL.md — no agent-specific references to principles
- Deferred TODOs: none
-->

# nix-config Constitution

Scope: this repository (a NixOS / nix-darwin / home-manager flake) and any feature built in a
fork that this repository carries as a patch or builds as a flake input, such as the niri fork
behind the `niri-virtual` input.

## Core Principles

### I. Atomic, Revertable History

- Every commit MUST do exactly one granular thing, and reverting it alone MUST leave the tree
  building, provided it built before.
- History MUST NOT be squashed. Fixes to an unmerged branch's own commits go in as
  `fixup!`/`amend!` commits against the commit they correct.
- Commits and pull requests MUST NOT carry AI attribution (`Co-Authored-By: Claude`,
  session links, "Generated with" footers).
- Branches land on the default branch by local rebase and fast-forward push, so signatures
  survive; server-side merges are a fallback, and squash merges are never used.

Rationale: per-change revert is the cheapest rollback a flake has; squashing destroys it.

### II. Test First, Evidence Before Done

- New behaviour MUST start with a test that fails without the change, where the behaviour is
  testable at all; untestable glue MUST be named as such in the commit or plan.
- A change MUST NOT be reported done, fixed or passing without the command output that shows
  it: the build, the test run, or the live check.
- Nix changes MUST at least evaluate and build the affected outputs (`just check`, or a
  targeted `nix build`) before commit.

Rationale: plausible-looking fixes to compositors, drivers and hosts fail in ways only a run
reveals.

### III. Infrastructure as Code, Live Changes by Consent

- Changes to hosts and services MUST be made in this repository (or the owning IaC repo)
  and applied by the normal switch/deploy path or CI.
- Direct mutation of live systems (a running host, cluster or cloud account) MUST NOT happen
  without the owner's explicit permission for that specific change, even on personal infra.
- Interactions with external systems MUST check current state before mutating, be safe to
  re-run, and retry transient failures with backoff.

Rationale: the flake is the record of truth; out-of-band edits drift and get lost.

### IV. Errors Carry Context

- Errors MUST NOT be swallowed; each is handled or propagated with enough context that the
  log line alone names the failing operation and its inputs.
- Rust code MUST pass `cargo fmt --check` and `cargo clippy -- -D warnings`, and MUST NOT use
  `unwrap`/`expect` outside tests and `main`'s top-level error handling.
- Shell and Python embedded in Nix MUST resolve their tools from Nix, never assume `PATH`.

Rationale: most debugging time in this repo went to failures that reported nothing useful.

### V. Right Altitude, Single Source of Truth

- Solve the problem asked: no speculative generality, no unrelated refactors in the same
  change, abstractions only on the second or third real use.
- Search for an existing helper or option before writing a new one.
- A value used in more than one place (SSH keys, hostnames, ports, versions) MUST live in one
  place and be referenced, not copied.

Rationale: a flake managing a dozen hosts multiplies every duplicate and every
over-abstraction.

### VI. Record the Why

- A hard-won lesson (a non-obvious root cause, a rejected alternative, a workaround's
  reason) MUST be recorded as an ADR in `docs/adr/`, with the relevant topic doc updated, in
  the same pull request as the change.
- Comments explain only non-obvious *why*; they never restate the code or cite tickets.

Rationale: commit messages and agent memory are not where the next reader looks.

### VII. Fork Patches Are Generated

- A patch this repository carries against an upstream or fork MUST be generated from fork
  commits (`git diff <base> HEAD`), never edited by hand.
- Fixes MUST land in the fork as commits with their tests first, then the patch is
  regenerated (or, for a fork built as a flake input, the input updated) and the affected
  package rebuilt.
- Files that belong to this repository's tooling (`.specify/`, `.claude/`) MUST NOT be added
  to a fork whose diff becomes a patch.

Rationale: a hand-edited patch loses its history, its tests and its upstreamability.

## Operational Constraints

- Shared configuration (CLAUDE.md, skills, scripts) runs on many machines: it MUST NOT assume
  a tool is installed or hard-code machine-specific paths; probe with `command -v` and fall
  back.
- Times in files, logs and reports MUST be ISO 8601 UTC (e.g. `2026-09-28T14:03:22Z`); text is
  UTF-8.
- Formats both humans and machines read (Markdown tables, JSON, CSV) are preferred over
  free-form dumps.
- Secrets live only in sops-nix (`secrets/`, `.sops.yaml`); they MUST NOT appear in the Nix
  store, logs or commits.

## Development Workflow & Quality Gates

- Work happens on a branch off the default branch, never on it directly.
- Before a pull request: the change builds, its tests pass, commit hooks (`prek`) pass, and
  each commit stands alone per Principle I.
- Pull request bodies state what changed, why, and what was verified with the evidence.
- Spec-driven features (`specs/NNN-*`) follow spec → plan → tasks → implement; the plan's
  Constitution Check MUST list any principle a design bends and justify it in its Complexity
  Tracking table.

## Governance

- This constitution overrides tool defaults and skill defaults; the owner's direct
  instructions in a session override this constitution for that session only.
- Amendments are made by pull request that updates this file, bumps the version and states the
  impact in the Sync Impact Report at the top.
- Versioning: MAJOR for removing or redefining a principle, MINOR for adding a principle or
  materially expanding one, PATCH for wording and clarifications.
- Every plan's Constitution Check and every review MUST check compliance; a violation is
  either fixed or justified in writing.
- Runtime guidance for agents lives in `CLAUDE.md` and the repository's skills
  (`.claude/skills/`); they MUST stay consistent with this file.

**Version**: 1.0.1 | **Ratified**: 2026-09-28 | **Last Amended**: 2026-09-29
