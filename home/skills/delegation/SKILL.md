---
name: delegation
description: Use before spawning a sub-agent (Agent tool), deciding whether a batch of similar calls belongs in the main loop, whether to run several in parallel, or when a delegated result came back wrong or incomplete. Covers model tier/cost/speed (haiku/sonnet/opus/fable), Explore vs general-purpose, background execution, self-contained prompts, Copilot CLI delegation, and delegating to a locally-hosted model. Not for escalating to a stronger model — see `consulting`.
---

# Delegation

The main loop runs on a fast, capable model reserved for voice, scope, and
judgement. Anything that needs none of those belongs on a cheaper model in a
sub-agent, not ground through inline.

## Cost and speed by tier

Snapshot from [claude.com/pricing](https://claude.com/pricing), checked
2026-09-19 — verify current numbers there before quoting them, since prices
change and this table will drift:

| Tier | Input / output per MTok (million tokens) | Roughly vs. Haiku |
|---|---|---|
| Haiku 4.5 | $1 / $5 | 1x — the fastest tier |
| Sonnet 5 | $2 / $10 | ~2x |
| Opus 5 | $5 / $25 | ~5x |
| Fable 5.1 | $10 / $50 | ~10x |

Haiku is the cheapest and fastest tier. Per that same pricing page, Opus's
base speed is not fast — it has an optional "fast mode" at double its own
price for roughly 2.5x the speed — and Fable is priced and positioned for
long-running agentic work, not quick bulk calls.

The gap compounds with volume: 50 haiku-tiered calls cost roughly what 25
sonnet-tiered ones would (Sonnet's ~2x table ratio) for work that doesn't
need sonnet's judgement — or 10 opus-tiered ones (~5x), if that's the
comparison at hand. That gap, not a stylistic preference for cheap models,
is the whole case for
delegating aggressively rather than defaulting every call to whatever tier
the main loop runs on.

GitHub Copilot CLI delegation (below) moved to the same unit as this table —
since 2026-06 Copilot bills per-token in "AI Credits" ($0.01/credit) instead
of premium-request multipliers, so its models are directly $/MTok comparable
to Claude's, not a separate currency. Claude models cost the same through
Copilot as through Anthropic's own API — no markup. See
[delegate-to-copilot.md](delegate-to-copilot.md) for the comparison and when
it beats an Agent-tool sub-agent on price. (The multiplier system still
exists for legacy annual-plan subscribers who didn't move to usage billing,
but that plan doesn't get new models — check which billing mode an account
is on before assuming either applies.)

## When to delegate at all

The cost and speed gap above means the bar for delegating is lower than it
feels: even a handful of clearly mechanical calls (not just runs of 5+) can
be worth a haiku sub-agent, since haiku-tier cost is close to negligible and
`run_in_background` hides the wall-clock cost from the main loop. The
counterweight is spawn overhead, not per-call cost: a sub-agent pays for
`CLAUDE.md`, git status, and its tool schemas on every spawn
(general-purpose; Explore/Plan skip the first two — see below), so a batch
of 1-2 calls often isn't worth a fresh spawn even at haiku prices. Bulk
`gh`/GraphQL queries, web searches, log trawls, per-file mechanical edits,
and dependency-bump enumeration are the shapes that clear that bar.

Code reading stays inline: Read/Grep/Glob to understand code you are about to
work on are cheap and belong in the main loop — never route ordinary
exploration through a sub-agent. Delegate a search sweep only when you need
the *conclusion*, not the file contents, AND it spans many files or areas you
won't otherwise open.

## Running sub-agents in parallel

Multiple `Agent` calls in **one message** run concurrently; one per message
runs sequentially.

- **Give each agent a disjoint scope.** One independent problem domain per
  agent — a specific file, subsystem, or query — not an overlapping one;
  agents with overlapping scope duplicate each other's work.
- **Reads fan out, writes don't.** Parallelize independent investigations or
  lookups freely. Parallel *implementation* agents editing real code
  conflict with each other — serialize those, or isolate each in its own
  worktree ([git/worktrees.md](../git/worktrees.md)).
- **Size the fan-out to the task, not habit**: ~1 agent for simple fact-
  finding, 2-4 for a comparison across sources, 10+ only for genuinely broad
  research — [Anthropic's own multi-agent research
  system](https://www.anthropic.com/engineering/multi-agent-research-system)
  measured over-fanning simple queries as the main early failure mode.
- **Don't fan out** when a subtask depends on another's output, would race
  on a shared file or resource, is exploratory (you don't yet know what's
  broken — sequential probing beats parallel guessing), or is short enough
  that spawn overhead dominates.
- **Cost vs. speed**: parallel spawns don't share total cost with serial —
  same aggregate tokens either way, just compressed into less wall-clock.
  Anthropic measured up to 90% less wall-clock against roughly 15x the token
  spend of a single agent for genuinely parallel research. It's a speed
  lever, not a cost lever, and each spawn still pays its own overhead (see
  above) with no cache sharing between siblings.
- **Hard cap**: Claude Code defaults to 20 concurrent sub-agents
  (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, configurable, version-gated —
  check current behaviour if this matters). The main-loop context budget
  binds first in practice — every result lands in your context, so N
  detailed replies can refill the window you were trying to protect. Cap
  each reply length (see "Writing the prompt") more aggressively the wider
  the fan-out.

## Picking the model: default to haiku

Default every delegated task to **haiku**. Step up to **sonnet** only when the
task itself — not the batch it's part of — requires judgement: picking which
of several ambiguous candidates is correct, multi-step reasoning, synthesizing
a conclusion from heterogeneous sources, or writing/editing code. Unsure which
tier? That uncertainty is itself evidence the task needs judgement — pick
sonnet.

Before defaulting to haiku, check whether Copilot's `delegate.sh` (Luna) is
the better fit instead — see delegate-to-copilot.md's "Separately metered
Claude and Copilot allowances" when the account has independent quotas for
each and Claude's is the one worth conserving.

**The test:** could a competent but literal-minded assistant, with no
discretion, get this right by following your instructions exactly? If yes,
haiku. If correctness depends on interpreting ambiguity, weighing trade-offs,
or catching something you didn't explicitly name, sonnet.

Haiku-shaped work (default here unless the task itself says otherwise):
- Enumerating or extracting from a known, homogeneous source: listing PRs
  matching a filter, pulling fields out of `gh`/GraphQL/API responses,
  grepping logs for a known pattern.
- Summarizing many similar items into one line each, with a format you
  specify exactly (e.g. "one line per PR — number, state, mergeable").
- Mechanical, well-specified edits repeated across many files: a rename, a
  fixed find-replace, a version-bump in a known location.
- Format conversion against a fixed, unambiguous schema.

Sonnet-shaped work:
- Writing or editing code beyond a mechanical, fully-specified substitution.
- Judging *which* of several plausible results is the right one.
- Any step whose output feeds a decision rather than a report.
- A sweep whose success criteria can't be fully written down in the prompt —
  if you can't specify "correct" up front, the sub-agent needs judgement to
  fill the gap, which means sonnet.

When a batch mixes trivial items with a few judgement calls, split it (haiku
for the mechanical slice, sonnet for the rest) rather than guessing one tier
for the whole thing.

## Explore vs general-purpose

For a read-only search/exploration sweep, prefer the Explore (or Plan)
sub-agent over general-purpose: per [Claude Code's own
docs](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup),
Explore/Plan skip CLAUDE.md and git status at startup, while a
general-purpose agent pays for both on every spawn. Use
general-purpose only when the sweep needs tools Explore lacks (edits, writes,
MCP mutations).

## When a delegated result comes back wrong or incomplete

Don't patch it by hand and move on — that fixes this one result, not the next
one. Re-check the tier: a wrong result from a haiku-tiered task is often
evidence the task needed judgement after all (see the test above), so redo it
at sonnet rather than retrying the same tier. A wrong result at the right tier
means the prompt was underspecified — fix the prompt, not just the output.

## Writing the prompt

- Sub-agent prompts must be self-contained: every path, ID, query, and the
  exact output format — the sub-agent cannot see this conversation.
- Name the relevant skills in the prompt. A sub-agent gets no skill listing,
  so it cannot discover a skill — but it can invoke one by exact name. Inject
  only what the task needs: "invoke the `programming` skill, then read its
  languages/rust.md" for code work, "invoke `testing`" for tests, and so on.
  Skip this for Explore/Plan sweeps, which are read-only.
- Cap the reply length explicitly (e.g. "return at most 30 lines: one line
  per PR — number, state, mergeable").

## Delegating outside the Agent tool

Everything above picks a *model tier* for an Agent-tool sub-agent. GitHub
Copilot's own `copilot` CLI is a separate, external delegate with its
cheapest model (`gpt-5.6-luna`) priced below even Haiku and, on public
benchmarks, comparably fast and capable — read
[delegate-to-copilot.md](delegate-to-copilot.md) for the actual numbers and
when that beats a Claude sub-agent instead of assuming Claude tiers are
always the cheaper or only option.

A third option, for zero-marginal-cost text-only work with no cloud
dependency: a model running on your own hardware via an OpenAI-compatible
endpoint. Text in, text out by default, or an agent over one directory
through `delegate-to-local-agent.sh`: read-only, or with
`LOCAL_LLM_AGENT_EDIT=1` allowed to edit there, with a diff to review before
anything is kept. It never runs commands. Weaker than Haiku or Copilot's
Luna: on ali-desktop, a 35B mixture-of-experts model and a 9B write and
edit reliably from an exact spec, and only the 27B says correctly what code
does. So it fits a narrower slice of haiku-shaped work, with every result
reviewed. See
[delegate-to-local.md](delegate-to-local.md): its "Picking a model" table
first, then the measured scorecard.

## Never delegate

User-facing judgement, irreversible actions, or work whose context cannot be
compressed into a prompt.

## Related

- `consulting`: escalating to a stronger model when stuck, not delegating
  volume to a cheaper one.
- `programming`, `testing`, `git`, and other skills: name them explicitly in
  a sub-agent prompt when the delegated task needs their guidance.
- [delegate-to-copilot.md](delegate-to-copilot.md): delegating to GitHub
  Copilot's CLI instead of an Agent-tool sub-agent.
- [delegate-to-local.md](delegate-to-local.md): delegating to a
  locally-hosted model over an OpenAI-compatible endpoint.
