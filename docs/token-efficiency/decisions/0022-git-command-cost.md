---
id: "0022"
host: ali-desktop
date: 2026-11-25T11:30:00Z
finding: manual-2026-11-25-ali-desktop#git
decision: configure
reason: "git and gh are 7.8% of Bash script-candidate cost over 7 days ($6.55 of $83.51) and 11% over 30 days ($38.33 of $353.0); diff and show output is most of it and difftastic inflates git diff, so trim output in the git skill and pilot jj for the call count"
metric: { question: script-candidates, key: "sum:git-and-gh-shapes", baseline: 6.55, unit: usd/week }
acted_on: null
outcome: null
outcome_review: null
---
Asked by the owner: does a jj skill cut the tokens and time spent on git? Measured by hand
with `cc-obs-query automate` (7 days in full, 30 days to a $0.02 tail) on ali-desktop.

| Leading command (30 days) | Calls | Est. USD |
|---|---|---|
| `git diff` | 325 | 11.36 |
| `git show` | 188 | 5.04 |
| `git add` (mostly `git add && git commit`) | 668 | 4.31 |
| `git status` | 202 | 3.51 |
| everything else git or gh | 1,147 | 14.11 |

Output size drives cost, not call count: `git add && git commit` is a quarter of the calls
and an eighth of the cost. `diff.external` is difftastic on this host, and plain
`git diff` ran it: on 8 of the last 10 commits its output was 1.1x to 11.7x the patch
(310 KB against 199 KB in total, leaving out one 708 KB commit where it was smaller).
`git show` does not run it. `--stat` was 0.3% to 11% of the patch.

So jj alone would barely move the figure: it folds add-then-commit into one call (about
$1/week here) and removes interactive-rebase workarounds, which do not show as a separate
shape. The configure step is (1) compact-output rules in `home/skills/git/SKILL.md`:
`--stat` first, one path at a time, `--no-ext-diff`, no confirming `git log` after a
commit; (2) a jj pilot (`home/skills/git/jj.md`, `programs.jujutsu`) on nix-config only;
(3) `jj` in the ledger's `command_shape` vocabulary so the pilot is measurable.

Time is not answerable: tool-call records carry no duration by command shape. For scale,
the largest Bash-adjacent item is large-then-narrow Read at $67.58 over 30 days, about
twice all of git.

The baseline is a hand-summed aggregate: no single `automate` row carries it, so the
`sum:` key matches nothing: the digest reports the metric absent and `compare` emits no
row for it. Re-sum it by hand: the
`est_usd` of every 7-day shape row whose label mentions `git` or `gh` (sequences, $0.83 at
baseline, are left out). The next review compares that sum, plus the same for `jj`, against
this baseline, and checks that `git diff [cd]` and `git diff | head` fall.
