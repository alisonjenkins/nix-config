# 0041. Build the control centre in claude-monitor and couple loosely to cortexiphan

- Status: Proposed
- Date: 2026-10-12
- Design: [`specs/008-ai-control-centre/`](../../specs/008-ai-control-centre/)
  (`plan.md` Complexity Tracking, `research.md` D11)

## Context

FR-022 requires building on `claude-monitor`, which is its own repository with its own
flake input, CI and release train. The nix-config constitution scopes its rules to
"this repository" (plus forks it carries as patches or flake inputs), so putting the
code elsewhere is a deviation that needs a recorded reason.

Cortexiphan is the user's planned knowledge and task store. Facts checked in its
repository on 2026-10-12: it is in Phase 0; `NodeKind` is `#[non_exhaustive]` with
`Project`, `Task` and `Custom`; connectors dedupe on `ExternalRef{system,id}`; the CLI
creates only notes and tasks and MCP `node_create` rejects `project`; there is no file
import; local CLI mode is in-memory and persists nothing. It cannot be a dependency of
the control centre (FR-027).

## Decision

- **Code home.** The code lives in the `claude-monitor` repository as one Cargo
  package: a library crate (`claude_monitor`) and a thin binary, with cargo features
  `tui` and `web`. With `default-features = false` the library is a runtime-agnostic
  core that cortexiphan can depend on when the two merge.
- **What nix-config carries.** Only the spec, these ADRs, the topic doc
  `docs/ai-control-centre.md` and the Home Manager wiring (units, tmux binding, hook
  registration, flake input bump).
- **Constitution deviation.** This departs from the scope line "this repository". The
  owner confirmed the choice on 2026-10-12. The deviation is listed in the plan's
  Complexity Tracking table.
- **Cortexiphan coupling is loose:**
  - shared vocabulary (statuses map to cortexiphan's in one export module);
  - an idempotent JSON Lines export, one record per project, step, session and link,
    each carrying `external = {system:"ai-control-centre", id:<uuid>}` and an
    `author`, so re-import is a no-op on `(system, id)` (SC-009);
  - links between the two sides, with the linked side read best-effort through
    `cortexiphan --json node get` only when `CORTEXIPHAN_SERVER` and a token are set,
    and "other side unavailable" otherwise;
  - no live shared database;
  - the control centre works with cortexiphan absent.
- The ingest side is cortexiphan work and out of scope here. This feature delivers a
  documented, versioned, schema-checked format and a test that re-export is
  byte-stable.

## Alternatives rejected

| Option | Why not |
|---|---|
| A new repository | Discards `claude-monitor`'s tested hook and TUI code and adds a third release train. |
| A copy inside nix-config | Forks the tool, breaks its CI and release flow, and puts application code into the host configuration repo. |
| Writing to cortexiphan's store directly | Cortexiphan is Phase 0, has no file import and no persistence in local mode, and would make the control centre depend on a server (FR-027). |
| Sharing one live database with cortexiphan | Same dependency problem, and couples two schemas that are still moving. |

## Consequences

- The tool keeps its own CI (test, clippy `-D warnings`, fmt, cargo-deny) and release
  flow. nix-config only bumps the flake input.
- Spec, ADR and wiring changes are reviewed here; behaviour changes are reviewed in
  `claude-monitor`, whose PRs link to these records.
- Crates stay edition-agnostic (`claude-monitor` is edition 2021, cortexiphan 2024) so
  the merge can migrate them.
- A format change in cortexiphan's connector pattern means a new export version here,
  not a code dependency.

## Evidence

- `research.md` D11 records the cortexiphan facts above, read from its source on
  2026-10-12.
- Not yet shown: the byte-stable re-export test and the zero-duplicate re-import
  check (SC-009) are tasks in `tasks.md`.

## Revisit when

- Cortexiphan gains a file or API import for projects, making a direct integration
  cheaper than the export file.
- The merge into cortexiphan happens, at which point the library crate moves and this
  record is superseded.
- `claude-monitor` stops being a flake input of this repository.
