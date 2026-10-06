---
name: delegation
description: >-
  Use before doing a multi-step task yourself, not only once you're already considering a sub-agent: a multi-file sweep, several similar gh/GraphQL/API lookups, a log trawl, a round of mechanical edits across files, 2+ independent research questions, or any batch of same-shaped calls — check whether it belongs on a cheaper model, in a sub-agent, or fanned out in parallel before touching it inline. Also use when picking a model tier (haiku/sonnet/opus/fable), choosing Explore vs general-purpose, batching parallel Agent calls in one message, or when a delegated result came back wrong or incomplete. Covers background execution, self-contained prompts, Copilot CLI delegation, and delegating to a locally-hosted model. Not for escalating to a stronger model — see `consulting`.
---

# Delegation

The main loop runs on a fast, capable model reserved for voice, scope, and
judgement. Anything that needs none of those belongs on a cheaper model in a
sub-agent, not ground through inline.

## Before doing it yourself, check for these

These thoughts mean stop and re-read "When to delegate at all" and "Running
sub-agents in parallel" below — they're the moment this skill gets skipped:

| Thought | Reality |
|---|---|
| "It's faster to just do this myself" | True for one call. Not true for 2+ similar ones — spawn overhead is the only real cost, and `run_in_background` hides wall-clock. |
| "I'll do these files one at a time, it's simpler" | Independent reads/edits across files are exactly the fan-out case. Batch them into one message of parallel Agent calls. |
| "This is quick, not worth a sub-agent" | Quick and cheap-tier-shaped is the haiku case, not the skip-delegation case. |
| "I already started, I'll just finish it inline" | Sunk cost. If the remaining items are independent and same-shaped, hand the rest off. |
| "The user wants this done now" | Parallel sub-agents are faster wall-clock, not slower — fanning out serves urgency, it doesn't fight it. |
| "I need the output to reason over anyway" | Only true if you need the raw content, not a conclusion. A sweep whose result you'll summarize or act on belongs in a sub-agent even then (see `fork` in the Agent tool). |

## Cost and speed by tier

Prices from [claude.com/pricing](https://claude.com/pricing); intelligence
index and output speed from [Artificial
Analysis](https://artificialanalysis.ai/providers/anthropic) (medium effort).
Both checked 2026-09-28 — verify current numbers before quoting them, since
this table will drift:

| Tier | Input / output per MTok (million tokens) | Roughly vs. Haiku | AA intelligence index | Output tok/s |
|---|---|---|---|---|
| Haiku 4.5 | $1 / $5 | 1x | 15 | ~80 |
| Sonnet 5 | $2 / $10 | ~2x | 28 | ~60 |
| Opus 5.5 | $4 / $20 | ~4x | 51 (up to 58 at max effort) | ~82 |
| Fable 5.1 | $10 / $50 | ~10x | 49 (up to 53 at max effort) | ~56 |

Opus 5.5 replaced Opus 5 ($5 / $25, now listed under legacy models) and is
cheaper than it. The index shifts several points with effort/reasoning
settings, so compare tiers by rough gap, not exact integers; it also
measures benchmark reasoning, not long-running agentic work, which is where
Fable is positioned.

Haiku is the cheapest tier. Per that same pricing page, Opus's
base speed is not fast — it has an optional "fast mode" at double its own
price for roughly 2.5x the speed — and Fable is priced and positioned for
long-running agentic work, not quick bulk calls.

The gap compounds with volume: 50 haiku-tiered calls cost roughly what 25
sonnet-tiered ones would (Sonnet's ~2x table ratio) for work that doesn't
need sonnet's judgement — or ~12 opus-tiered ones (~4x), if that's the
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

The main loop is a manager: it scopes, judges, reviews what comes back, and
talks to the user. Everything else goes to the cheapest delegate that can do
it. The cost and speed gap above means the bar for delegating is lower than
it feels: two or more independent calls of the same shape already qualify,
since cheap-tier cost is close to negligible and `run_in_background` hides
the wall-clock cost from the main loop. Even a sonnet sub-agent under a
sonnet main loop pays off on a long sweep: the per-token price is the same,
but the sweep's output never enters the main context, which every later
turn re-reads. The
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
  worktree ([git/worktrees.md](../git/worktrees.md)). In Claude Code, spawn
  each writer with `isolation: "worktree"` and have it start by checking
  out the exact commit to build on (`git switch -c <branch> <sha>`), then
  commit there for you to cherry-pick. A worktree you create yourself and
  name in the prompt does not work: a sub-agent's shell is pinned to the
  parent session's worktree and refuses to run anywhere else.
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

### The per-machine ladder

Below haiku there is a cheaper rung, and which one depends on the machine.
The Model Routing mandate in `~/.claude/CLAUDE.md` names it (nix sets it
per host through `cheapDelegate`):

| Machine | First rung | Falls back to |
|---|---|---|
| Work (`cheapDelegate = "copilot"`) | Copilot's Luna via `scripts/delegate.sh` | haiku sub-agent when credits are exhausted or the task needs this session's tools or skills |
| Personal (default, `"local"`) | Local model via `scripts/delegate-to-local.sh` / `delegate-to-local-agent.sh` | haiku sub-agent when no profile is live or the task isn't haiku-shaped |

Both first rungs are text in, text out (the local agent mode adds read, and
optionally edit, over one directory). Neither runs commands, so anything
that needs Bash, `gh`, MCP tools, or skills goes straight to a sub-agent.

On a personal machine, check `list-local-profiles.sh` first; it is
read-only and cheap. Don't load a profile for one task, since loading takes
up to two minutes. Switch deliberately when a stretch of several
local-shaped tasks is ahead and it fits the free VRAM (see
[delegate-to-local.md](delegate-to-local.md)). On the work machine, a
credit-exhaustion error from `delegate.sh` is cached for 24h, so after one,
go straight to haiku for the rest of the session.

Review every result from the first rung before using it. It is weaker
(local) or external (Copilot) output, and wrong output costs more to redo
than a haiku call would have.

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
Copilot's own `copilot` CLI is a separate, external delegate whose cheapest
models (GPT-6 Luna, with `gpt-5.6-luna` as the script's next choice) are
priced well below Haiku and, on public benchmarks, faster and more capable
than it — read
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
