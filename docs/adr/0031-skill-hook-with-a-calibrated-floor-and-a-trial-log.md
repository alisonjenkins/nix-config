# 0031. Inject skill sections above a calibrated floor, and trial both hooks with a log

- Status: Proposed. Built; on trial on `ali-desktop`.
- Date: 2026-10-07
- Extends [0029](0029-embedding-retrieval-for-memory-and-skills.md) and
  [0030](0030-inject-confident-memories-and-use-a-catalogue.md).

## Context

The skills comparison in 0029 injected the top 3 sections for every query and got
the right source 95% of the time at $0.020 a query against $0.086 for loading whole
skill files. A hook cannot inject unconditionally: it would add about 500 tokens to
every prompt, off-topic ones included. It needs a floor, and no hook existed.

Every benchmark query also had a matching memory or skill. Real prompts mostly do
not, so the benchmark cannot say whether the hooks pay for themselves on real use.

## Decision

- Add `skill-recall` (same shape as `memory-recall`: `index`, `query`, a fail-open
  `hook`, plus `calibrate`) and an optional `modules.memoryRecall.skills` block.
  It injects up to 3 sections of at most 3,000 characters at or above **0.74**.
- Both hooks append a line per prompt (best score, matches, how many in full,
  tokens added, never the prompt) to a log, on by default, and
  `memory-recall log-summary` reads it.
- Enable both on `ali-desktop` as a trial, and decide on adopting the catalogue
  from the log, not from the benchmark.

## Alternatives rejected

Measured with `skill-recall calibrate` over 656 sections, 20 skills queries and the
30 off-topic prompts (`bench/results/skill-calibrate-top3.md`); recall is the right
section in the top 3:

| Floor | Recall | False injection (off-topic) | Tokens a prompt | Why not |
|---|---|---|---|---|
| none (the benchmark) | 95% | 97% | 507 | Injects on nearly every prompt. |
| 0.70 | 90% | 57% | 398 | More than half of off-topic prompts pay. |
| 0.72 | 85% | 37% | 327 | Closest competitor; the extra 15 points of recall cost 17 points of false injection and 90 tokens a prompt. |
| **0.74** | **70%** | **20%** | **238** | Chosen. |
| 0.78 | 55% | 3% | 93 | Misses nearly half. |

Skill scores overlap far more than memory scores: off-topic prompts reach 0.78,
while the right section falls below 0.74 for 30% of queries, so no floor is both
high-recall and low-noise, unlike the memory floors in 0030. Top 2 instead of 3
loses 5 to 10 points of recall at the same floor.

## Consequences

- **The skills saving is smaller than the benchmark's.** The listing of every skill
  stays in every session; the hook only spares the model loading a whole file, and
  injects 240 tokens on average whether or not it did.
- **Both hooks inject the nix-config project's memories into every project's
  prompts**, since the module names one memory directory.
- **Logging is on by default.** It records scores and counts, which identify no
  prompt; `logFile = null` turns it off.
- The negatives used for calibration are off-topic only: the memory `adjacent`
  prompts ("add a unit test for the parser") are things the programming and testing
  skills legitimately cover.

## Evidence

- `bench/results/skill-calibrate-top2.md`, `skill-calibrate-top3.md`; reproduce
  with `skill-recall calibrate` after `skill-recall index`.
- The module builds with `skills.enable` on and off (scratch flake pinned to the
  commit), and `ali-desktop`'s hooks list both scripts.
- Both hooks run against a live server: the examplarr prompt gets a memory in full,
  the assertion prompt gets a skill section at 0.85, the haiku and a 3-letter
  prompt get nothing, and `log-summary` reads the log.
- Single runs of a 20-query set; the floor is a judgement from one sweep.

## Revisit when

- The trial log shows more than a third of prompts getting an injection that the
  model did not use, or fewer than a tenth getting one at all.
- A third query set disagrees with the sweep by more than 5 points.
- Claude Code lets a hook trim the skill listing, which is where the larger saving is.
