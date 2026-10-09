# 0037. Review token use weekly in two tiers, unattended

- Status: Accepted, not yet built (T056, T059)
- Date: 2026-10-09

## Context

The stack collects logs, traces and metrics so token use can be cut. Without a
regular review that data becomes a swamp nobody reads. A timer (systemd user timer
on Linux, launchd `StartCalendarInterval` on macOS) runs `claude -p`
non-interactively, which the repo already does in `llm_run.rs`.

## Decision

Stage 1 uses a haiku-class model to run `cc-obs-query` commands for each question
in the versioned pack, follow up on anomalies with a bounded number of drill-downs
(one session detail per top offender), choose evidence references, and submit the
digest through `cc-obs-query digest --write`, which validates schema, size cap and
"no content" before saving. If stage 1 fails or hits its budget the runner falls
back to `cc-obs-query digest --baseline`, which runs the pack mechanically with no
model and marks the digest `stage1: "baseline"`. Stage 2 uses a stronger model
that reads only the digest and writes the findings. `--max-budget-usd` caps each
stage. Output goes to a per-host state directory, never straight into the
repository: the owner promotes findings into `docs/token-efficiency/` with their
decision (the system never commits). Missed runs are detected by comparing the
last digest's period end to now and catch up on the next run.

## Alternatives rejected

- **One strong-model stage over raw queries.** More tokens spent, contrary to the goal.
- **No-model digest only.** Rejected by the owner in clarification Q1.

## Consequences

Findings land in a state directory and the owner promotes them; the system never
commits. Stages run with `OTEL_RESOURCE_ATTRIBUTES=review.run=1`, excluded by
cc-obs-query so the review cannot pollute the data it analyses.

## Evidence

- Pending: `home/modules/observability-stack/tests/review-runner.bats` (T046) and the
  first real review (T061).

## Revisit when

A review's own cost (`own_cost_usd` in the findings file) is a noticeable share of the
tokens it saves, or the low-cost model keeps falling back to the baseline.
