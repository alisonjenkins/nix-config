# Running a token review

The weekly review is run by hand for now. The unattended runner (spec T056) and its
schedule (T059) are not built yet, so no digest or draft findings appear on their own.
The owner runs the `cc-obs-query` commands below, or the baseline digest
(`cc-obs-query digest --baseline --since 7d`). The scheduled version is planned
(ADR 0037); its output will go to `~/.local/state/token-review/<host>/`.

## Steps

1. **Get the digest.** Make one: `cc-obs-query digest --baseline --since 7d`
   (mechanical, no model). Once the scheduled runner exists, its newest `*.digest.json`
   in the state directory can be read instead. Check `stage1`
   (`model` or `baseline`), the `period`, `stack.gaps` and `own_cost`.
2. **Read the totals first.** Tokens, estimated cost, sessions. If the period is short or a
   gap covers most of it, say the review is thin and stop early.
3. **Rank.** For each question in the pack, take rows above its threshold. Order findings
   by estimated tokens saved per week, not by size alone: a tool that returns 40k tokens
   twice a week beats one that returns 2k a thousand times only if the arithmetic says so.
   Show the arithmetic.
4. **Drill into at most three items.** `cc-obs-query tool <name>`,
   `cc-obs-query session <id> --detail`, `cc-obs-query repeats`. Each is bounded; do not
   chase more than the top findings.
5. **Write at most five findings** in the format of
   `specs/007-local-observability-stack/contracts/review-formats.md`: title, estimated
   saving, evidence (references only), suggested action `build-tool`, `configure` or
   `dismiss`.
6. **Report your own cost.** Say what the review spent; it should be well under 1% of
   what it analysed.

## Starting questions

| Question | Look for | Usual fix |
|---|---|---|
| tool-result-size | Tools returning the most tokens per use | Bound or summarise the output, add `--limit`/filters |
| repeat-calls | Identical or near-identical calls in a session; big result then narrower query | A tool that does the narrow query directly |
| skills-loaded-unused | Skills activated and not used, or listed and never activated | Shorten the description, drop the skill |
| mcp-idle-servers | MCP servers connected but never called | Remove or defer the server |
| fixed-context-share | Fixed tokens per turn (instructions, listings) versus new content | Trim instruction files, move procedure into skills |
| cache-hit-low-sessions | Sessions with a low cache hit ratio | Find what invalidates the cache (editing early context, timeouts) |
| subagent-overhead | Sub-agents whose startup cost exceeds their task | Do the task inline or use a lighter agent type |
| memory-injected-ignored | Recalled items injected and not used | Raise the recall floor |
| compaction-frequency | Frequent compaction | Smaller tool outputs, earlier delegation |
| recall-failures | Recall errors | Fix the embedder, not the prompt |

## Dismissed and repeated findings

`cc-obs-query` marks a finding that was dismissed before. Show it as dismissed with the
earlier reason; raise it again only if its figure has grown by the pack's
`regrowth_factor` (default 1.5x).

## Decision records

One per finding, in `docs/token-efficiency/decisions/NNNN-slug.md` (front matter in
`contracts/review-formats.md`): `build`, `configure` or `dismiss`, a one-line reason,
the host, the baseline figure and unit. Do not write `outcome` yourself on the day;
a later review measures it with `cc-obs-query compare <question> --a <before> --b <after>`
and proposes `effective`, `ineffective` or `inconclusive`.

## Provisional

The thresholds and the ranking weights have not been tested on real data. After the first
real review, replace this note with what worked and what was noise.
