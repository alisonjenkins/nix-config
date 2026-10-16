# Running a token review

The unattended runner (`observability-stack-review`, ADR 0037) runs weekly when
`modules.observabilityStack.review.enable` is set, and writes to the review state
directory (default `~/.local/state/token-review/`): `digests/<date>-<host>.json`,
`findings/<date>-<host>.md` and `failures/` records. It has only run against fakes so far,
so check the newest `failures/` file first. This procedure is for a review run by hand,
or one that needs more than the runner's bounded drill-downs: the `cc-obs-query` commands
below, or the baseline digest (`cc-obs-query digest --baseline --since 7d`).

## Steps

1. **Get the digest.** Read the newest file in the state directory's `digests/`, or make
   one: `cc-obs-query digest --baseline --since 7d` (mechanical, no model). Check `stage1`
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

## Lessons from the first manual review (2026-10-16, ali-desktop)

- **Check the instrument before ranking on it.** Run one `claude -p "..." --model haiku
  --output-format json` and compare its `total_cost_usd` and four token counts with the
  stack's figures for that session. They matched exactly. The census split did not: it put
  the memory index at 0.45k tokens when it measured about 4.6k, so a lever picked from it
  was wrong.
- **Window totals use `increase(...[7d])`.** An instant `sum(counter)` covers only series
  that are live now and read about 100x low. `obs:token_cost_usd_estimate` sums cumulative
  counters before any `increase()`, so it over-counts over a window; do not use it for totals.
- **Tokens and cost count different things.** `--by tokens` is new input and output only;
  cost includes cache reads and writes. Cache reads were about 70% of cost, so fixed context
  re-read from cache is where the money goes even when its token share looks modest.
- **Measure fixed context by removing one component at a time**, summing input, cache read
  and cache creation of the one request: `--strict-mcp-config` (MCP), `--disable-slash-commands`
  (skills), `--tools ""` (built-in tool schemas), `--setting-sources ""` (settings, CLAUDE.md,
  hooks). It was 53.8k tokens here: built-in tool schemas 17.8k, MCP 9.5k, settings 9.3k,
  skills 3.0k, system prompt about 14k.
- **`cache-hit-low-sessions` is dominated by tiny sessions** whose only requests include the
  cold start. Skip sessions under about five requests, or weight by tokens, before drilling in.
- **`top subagent` splits by agent and model.** A row is one agent on one model, with the
  evidence reference `subagent:<agent>@<model>` (for example
  `subagent:general-purpose@claude-sonnet-5-5`); `--format detailed` shows the model as its
  own field. The same agent on two models is two rows, so add them for an agent total.
- **A tool "saves tokens" only if it replaces the result.** A PostToolUse hook that only adds
  `additionalContext` adds tokens. Test replacement with a positive control: on Claude Code
  2.1.293, `updatedToolOutput` replaced a Bash result only as `{stdout, stderr, interrupted,
  isImage}`; a bare string was ignored.

## Provisional

The thresholds and the ranking weights are still untested beyond that one review.
