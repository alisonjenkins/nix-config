# 0033. Route more work to cheap delegates; Haiku 5.5 first on Copilot

- Status: Accepted
- Date: 2026-10-08

## Context

On the work laptop the Claude token balance burned too fast, because too little
work reached the Copilot delegate (a separate balance). On the personal
machine the local model was not being loaded and haiku sub-agents were
underused.

The cause is in three places:

- The always-loaded Model Routing mandate
  (`home/programs/shared-mandates.nix`) sent only text-in, text-out work to
  Luna. Anything needing skills went to haiku.
- The personal rung used the local model only when a profile was already
  live, and nothing told the agent to load one.
- The `delegation` skill said "unsure which tier? pick sonnet" and needed two
  independent calls before delegating.

## Decision

Work machine. The Copilot delegate (`scripts/delegate.sh`) is the default for
single self-contained steps: specified code, tests, config edits, drafts,
first-pass reviews, repo and log sweeps. Skills can be passed by name, so
needing one is no reason to skip it. A haiku sub-agent is for when Copilot
credits run out, or the step needs MCP tools or this session's context.

Personal machine. If no local profile is live, load one with
`switch-local-profile.sh` in the background (its VRAM fit check refuses a
profile that will not fit beside a game). Use a haiku sub-agent until it is
up. Load once per session.

Tiers. Haiku-shaped work now includes specified code with tests, drafts,
first-pass reviews, and multi-step tasks with a stated done-check. Sonnet is
for open design, and for output that feeds an irreversible or unchecked
decision. If unsure, start cheaper when the result is cheap to check; step
up if the check fails.

Model order. `delegate.sh` tries `claude-haiku-5.5`, `gpt-6-luna`,
`gpt-5.6-luna`, then `claude-haiku-4.5`. A rejected ID falls through. A
policy or "not enabled" rejection falls through only when the output names
the model tried (wording is a guess). Haiku 5.5 may need Copilot CLI 1.0.93+.

Delegated prompts must ask for the check to be run and its output shown.
Haiku 5.5 at low or medium effort can skip the check, skip a search, or stop
early on a long prompt.

## Alternatives rejected

- **Keep the narrow routing, only raise Luna's use.** The gap is in the
  mandate. Moving Luna's share alone leaves skill-needing work on haiku.
- **Make Luna first for bulk work.** Luna used about a third of Haiku 5.5's
  output tokens on the Artificial Analysis index, so it likely costs less per
  task. No switch exists to put it first for bulk runs.
- **Pin sonnet for all code.** Highest cost per step. Not measured here, so no
  evidence it is needed when a check can catch the errors.

## Consequences

- Delegated prompts get longer: spec, done-check, and the check's output.
- Cheaper-model results need review (diff, tests). "Done" is not evidence.
- Same token price as Luna ($0.10/$0.50 per MTok), but Haiku used about 3x the
  output tokens on the Artificial Analysis index, so per task it likely costs
  more (inferred, not measured).
- `model: "haiku"` in Claude Code means Haiku 5.5 only from v2.1.293 on the
  Anthropic API. On 2026-10-08 2.1.286 was installed, so it still meant
  Haiku 4.5.

## Evidence

- Use: PRs #523 and #524 in alisonjenkins/nix-config.
- Haiku 5.5 GA in Copilot 2026-10-07. The ID `claude-haiku-5.5` is derived from
  the CLI changelog (`claude-opus-5.5`, `claude-fable-5.1`), unconfirmed.

## Revisit when

- `claude-haiku-5.5` is rejected on a real Copilot account.
- Measured per-task cost shows Haiku 5.5 above GPT-6 Luna. Then Luna goes first.
- Haiku 5.5 results fail review often enough that longer prompts do not
  cover it. Then code tiers move back toward sonnet.
