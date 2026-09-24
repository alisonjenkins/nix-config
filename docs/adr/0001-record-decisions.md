# 0001. Record decisions as ADRs

- Status: Accepted
- Date: 2026-09-24

## Context

This repo works around a long list of undocumented behaviour in Steam, niri,
gamescope, Proton and the kernel. The reasons lived in code comments, commit
bodies, design specs under `docs/superpowers/specs/`, and chat. The specs
record how a design was reached, but not which parts of it are still load
bearing, and they go stale as the design moves on.

On 2026-09-23 and 24 a Remote Play fault took most of two days. A large part
of that went on re-deriving facts that had already been learned, and on
testing theories the existing evidence already ruled out.

## Decision

Decisions that shape behaviour get a short record in `docs/adr/`: context,
decision, rejected alternatives, consequences, evidence, and the observation
that would make it wrong. Topic docs such as
`docs/steam-remote-play-streaming.md` stay the map and link here. Design specs
stay as the history of how a design was reached.

## Alternatives rejected

- **Comments in the Nix files.** They explain a line, not a choice between
  designs, and they vanish with the code they sat on.
- **The design specs alone.** They describe one change at one point in time.
  Nobody reads four specs to find out whether a detail still matters.

## Consequences

A change that contradicts a record needs a new record. That is deliberate
friction.

## Revisit when

A mistake recorded here gets made again. Then find out why the record was
missed.
