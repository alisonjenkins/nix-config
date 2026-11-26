# Skill decision records

Per-skill ADRs: why a rule in one skill under `home/skills/` is the way it
is. Collection-wide decisions live in [`../adr/`](../adr/README.md), under
Skills. The layout is set by
[ADR 0064](../adr/0064-keep-skill-adrs-at-two-levels.md).

Each skill numbers its own records from 0001 and uses the template in
[`../adr/README.md`](../adr/README.md#template). A skill cites a record as
"(decision <skill>/NNNN)". Supersede a record; never edit it to change
history.

## ci

| # | Decision | Status |
|---|---|---|
| [0001](ci/adr/0001-ci-skill-and-ci-audit-command.md) | A ci skill for pipeline design, and /ci-audit to apply it | Accepted |

## git

| # | Decision | Status |
|---|---|---|
| [0001](git/adr/0001-merge-by-rebasing-locally-and-pushing.md) | Merge by rebasing locally and pushing, not with GitHub's rebase | Accepted |
