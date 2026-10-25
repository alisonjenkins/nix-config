---
name: delegation
description: >-
  Use before doing a multi-step task yourself, not only once you're already considering a sub-agent: a multi-file sweep, several similar gh/GraphQL/API lookups, a log trawl, a round of mechanical edits across files, 2+ independent research questions, or any batch of same-shaped calls — check whether it belongs on a cheaper model, in a sub-agent, or fanned out in parallel before touching it inline. Also use when picking a model tier (haiku/sonnet/opus/fable), choosing Explore vs general-purpose, batching parallel Agent calls in one message, or when a delegated result came back wrong or incomplete. Covers background execution, self-contained prompts, Copilot CLI delegation, and delegating to a locally-hosted model. Not for escalating to a stronger model — see `consulting`.
metadata:
  summary: "Use before any multi-step sweep, batch of similar lookups, or mechanical edits: pick a cheaper model or sub-agent, fan out in parallel."
---

# Delegation

The main loop runs on a fast, capable model reserved for voice, scope, and
judgement. Anything that needs none of those belongs on a cheaper model in a
sub-agent, not ground through inline.

## Routing

| Doing | Read |
|---|---|
| Quoting a price, index or speed figure; comparing tiers; checking which model `model: "haiku"` runs | [tiers.md](tiers.md) |
| Choosing the first rung on the work machine (Copilot/Luna) or a personal machine (local model); loading a local profile; credit exhaustion | [ladder.md](ladder.md) |
| Delegating to GitHub Copilot's CLI | [delegate-to-copilot.md](delegate-to-copilot.md) |
| Delegating to Google's Antigravity CLI (Gemini, `agy`) | [delegate-to-gemini.md](delegate-to-gemini.md) |
| Delegating to a locally-hosted model | [delegate-to-local.md](delegate-to-local.md) |
| Several code-writing sub-agents in one project | [parallel-writers.md](parallel-writers.md) |

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
| "Luna can't handle code or commands, so I'll do it inline" (work machine) | It wrote and ran tests, edited manifests and reviewed diffs in testing; `read-shell` and `write-shell` run commands. Inline work burns the Claude balance. Try the Copilot delegate first. |
| "I need the output to reason over anyway" | Only true if you need the raw content, not a conclusion. A sweep whose result you'll summarize or act on belongs in a sub-agent even then (see `fork` in the Agent tool). |

## Cost and speed by tier

Haiku costs a tenth of Haiku 4.5, and "haiku" in this skill means Haiku 5.5
($0.10 / $0.50 per MTok): Sonnet is ~20x that, Opus ~40x, Fable ~100x. Prices
and index figures drift, so verify before quoting. Full table, which model
`model: "haiku"` runs per Claude Code version, and Haiku 5.5's weak spots (ask
for the check to be run and read its output): [tiers.md](tiers.md).

The gap compounds with volume: 50 haiku-tiered calls cost roughly what 2.5
sonnet-tiered ones would for work that doesn't need sonnet's judgement. That
gap, not a stylistic preference for cheap models, is the whole case for
delegating aggressively rather than defaulting every call to whatever tier
the main loop runs on. Copilot bills per-token too, so its models are directly
comparable (see [delegate-to-copilot.md](delegate-to-copilot.md)).

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
of 1-2 calls rarely paid off at Haiku 4.5 prices. At Haiku 5.5's $0.10 / $0.50
the startup tokens cost a fraction of a cent, so the real cost left is the
prompt you write and the latency. Delegate a single self-contained step
whenever writing its prompt is shorter than doing it, and keep inline only
what you must read to reason over. Bulk
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
- **Several writers in one project** (scope split, integration, reviewer,
  usage-limit and orphan-process handling): read
  [parallel-writers.md](parallel-writers.md).
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

Default every delegated task to **haiku**. On the work machine
(`cheapDelegate = "copilot"`) the default is the Copilot delegate (`delegate.sh`: Haiku 5.5, then Luna)
instead; read "The per-machine ladder" below before choosing a sub-agent
tier. Step up to **sonnet** only when the
task itself — not the batch it's part of — requires judgement: picking which
of several ambiguous candidates is correct, multi-step reasoning, synthesizing
a conclusion from heterogeneous sources, or writing code whose design is still
open. Unsure which tier? Start on the cheaper one when the result can be
checked cheaply (tests, a diff, a grep), and step up if the check fails.
Pick sonnet outright only when a wrong answer would be acted on without a
check.

For a haiku-shaped step with no need for MCP tools, spawn `subagent_type: "haiku-worker"`:
it is pinned to Haiku and carries a short tool list, so forgetting `model` cannot make
it run on Sonnet.

**Set `model` on every Agent call that should not run on Haiku.** An Agent call without
`model` now falls through to `CLAUDE_CODE_SUBAGENT_MODEL`, which the nix config sets to
`haiku`; name `sonnet` or a higher tier explicitly when the step needs judgement.
Measured by the observability stack over
2026-10-09/16 on `ali-desktop`: `general-purpose` sub-agents were 55.8% of
estimated cost, and `cc-obs-query top subagent --by cost` (which splits by model)
put 99.78% of sub-agent cost on Sonnet and 0.18% on Haiku. The nix config sets
`CLAUDE_CODE_SUBAGENT_MODEL` to `haiku`; since Claude Code 2.1.251 it only applies when
neither the Agent call nor the agent definition names a model, so per-agent `model:`
still wins, including the consultant agents whose `model:` is deliberate.

**Put edit-and-build workers on Haiku, and bound their runs.** One orchestration day on
`ali-desktop` (2026-10-16, 37 sub-agents, $452 at list price) showed that 36 of 37 runs were
Bash and Edit loops with a build or test as the done-check, a median of 124 requests, and
that cache reads were 86% of sub-agent cost: a long run re-reads its growing context on every
request, and the periodic progress summaries re-read it again. Cache reads cost $0.20 per
million tokens on Sonnet and $0.01 on Haiku. So when the done-check is a build or test, spawn
`haiku-worker`, and keep Sonnet for steps whose design is still open. Give each agent a narrow
scope and tell it to commit early and hand back with the state at about 150 requests; start a
fresh agent for the next phase rather than letting one context grow. Tried on 2026-10-16:
two shipped Sonnet tasks (a 3-test census fix, and an 8 s wait plus pressure logging in two
commits) replayed on `haiku-worker` from their original bases both passed the full test
suite and clippy when re-run by hand, in 23 and 79 tool calls against Sonnet's 26 and 69,
10 to 40% slower. The three `haiku-worker` runs in those two hours (those two and a
measurement task) cost $0.27 in total. Two caveats: the specs were fully written (the census diagnosis was
given), and Haiku found the same 16 s worst case as Sonnet only because the prompt asked for
anything it was unsure about. Give Haiku a spec and a done-check, and ask for doubts; keep
root-cause hunting on Sonnet.

### The per-machine ladder

Below haiku there is a cheaper rung, and which one depends on the machine.
The Model Routing mandate in `~/.claude/CLAUDE.md` names it (nix sets it
per host through `cheapDelegate`):

| Machine | First rung | Falls back to |
|---|---|---|
| Work (`cheapDelegate = "copilot"`) | Copilot's Haiku 5.5, falling back to Luna, via `scripts/delegate.sh` (the "Luna" below means this rung) | haiku sub-agent when credits are exhausted or the task needs MCP tools or context only this session has |
| Personal desktops and laptops (`cheapDelegate = "gemini"`) | Antigravity CLI (Gemini) via `scripts/delegate-to-gemini.sh`, see [delegate-to-gemini.md](delegate-to-gemini.md) | haiku sub-agent when agy is signed out or out of quota or the task needs MCP tools or session context; a live local model for text-only work |
| Personal (default, `"local"`) | Local model via `scripts/delegate-to-local.sh` / `delegate-to-local-agent.sh` | haiku sub-agent when no profile is live or the task isn't haiku-shaped |

The default is to hand first-rung-shaped work (a single self-contained step
qualifies) to the first rung rather than do it inline or spawn a sub-agent:
Luna on the work machine, the local model on a personal one. MCP tools and
commands outside Luna's `read-shell`/`write-shell` lists go straight to a
sub-agent; needing a Claude skill is not a reason to skip Luna. What counts as
Luna-shaped or local-shaped, loading a local profile, the
credit-exhaustion cache, and why the first rung no longer wins on price alone:
[ladder.md](ladder.md).

Review every result from the first rung before using it. It is weaker
(local) or external (Copilot) output, and wrong output costs more to redo
than a haiku call would have.

**The test:** could a competent assistant, given your instructions and the
files, get this right without a design decision of its own, and can you check
the result cheaply (tests, a diff, a grep)? If yes, haiku. If correctness
depends on interpreting ambiguity, weighing trade-offs, or catching something
you didn't explicitly name, sonnet. Haiku 5.5 scores above Sonnet 5 on the
Artificial Analysis index, but that index measures benchmark reasoning, not
long agentic work, so lean on the check, not on the tier's reputation.

Haiku-shaped work (default here unless the task itself says otherwise):
- Enumerating or extracting from a known, homogeneous source: listing PRs
  matching a filter, pulling fields out of `gh`/GraphQL/API responses,
  grepping logs for a known pattern.
- Summarizing many similar items into one line each, with a format you
  specify exactly (e.g. "one line per PR — number, state, mergeable").
- Mechanical, well-specified edits repeated across many files: a rename, a
  fixed find-replace, a version-bump in a known location.
- Format conversion against a fixed, unambiguous schema.
- Writing or editing code from a clear spec, and writing tests for it, when
  tests or a diff can verify the result.
- Drafts: commit and PR text, doc sections, release notes from a given diff.
- First-pass reviews and research summaries, read as a lead list, not a
  complete one.
- Multi-step investigations and tool-driven tasks (run, read, fix, re-run)
  with a stated done-check such as a test, a build or a grep. Haiku 5.5 is
  positioned for sub-agent work and scores above Sonnet 5 on the
  intelligence index, so these no longer need sonnet by default; the
  done-check is what catches its "reported done without running it" misses.
- Build, benchmark, corpus-assembly and run-the-suite steps with a stated done-check
  (a build exit code, a results file), even when they take many turns. Split them from
  the fix-the-code step, which stays on Sonnet. Evidence: on 2026-10-16/17 one session
  spawned about 30 sub-agents and set `model: sonnet` on all but one, including
  "Build integration/parity-N" and "Assemble corpora" steps. Sonnet agents were about
  $417 of the night's spend and Haiku about 0.1%; Sonnet costs about 20x Haiku per token.

Sonnet-shaped work:
- Writing code whose design is still open, or whose spec you cannot write
  down.
- Judging *which* of several plausible results is the right one.
- Any step whose output feeds an irreversible or unchecked decision rather
  than a report or a diff you will review.
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

An agent's report is a claim, not a result. Before acting on a load-bearing one (a field
name, a version, "this works on your build"), run the cheapest positive control yourself.
One research report said a hook field replaced tool output while bug reports said it did
not; a ten-line test on the installed build settled it. Review an agent's diff as you
would your own, and check it against the original failure, not against its summary.

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
- Tell the agent to read with the Read tool's `offset` and `limit` and to search with the Grep
  tool, not `sed -n` or `grep` through Bash, and to set a repeated environment variable (such as
  `CARGO_TARGET_DIR`) once for the run. In last week's transcripts (sub-agents included, token
  figures estimated as bytes/4), `sed -n` ranges returned about 1.4M tokens and `grep -n` about
  1M, and 115 Bash calls repeated an identical `env CARGO_TARGET_DIR=...` prefix.

## Delegating outside the Agent tool

Everything above picks a *model tier* for an Agent-tool sub-agent. GitHub
Copilot's own `copilot` CLI is a separate, external delegate whose cheapest
models (Haiku 5.5 first, then GPT-6 Luna, then `gpt-5.6-luna`) are priced at
or below Haiku 5.5; read [delegate-to-copilot.md](delegate-to-copilot.md) for
the numbers and when that beats a Claude sub-agent.

A third option, for zero-marginal-cost text-only work with no cloud
dependency: a model running on your own hardware via an OpenAI-compatible
endpoint. Text in, text out by default, or an agent over one directory
through `delegate-to-local-agent.sh`: read-only, or with
`LOCAL_LLM_AGENT_EDIT=1` allowed to edit there, with a diff to review before
anything is kept. It never runs commands. It takes spec'd code, tests,
drafts, summaries and extraction, not "explain what this does", with every
result reviewed by a diff or a test run (ali-desktop measurements in
[ladder.md](ladder.md)). See [delegate-to-local.md](delegate-to-local.md): its
"Picking a model" table first, then the measured scorecard.

## Never delegate

User-facing judgement, irreversible actions, or work whose context cannot be
compressed into a prompt.

## Related

- `consulting`: escalating to a stronger model when stuck, not delegating
  volume to a cheaper one.
- `programming`, `testing`, `git`, and other skills: name them explicitly in
  a sub-agent prompt when the delegated task needs their guidance.
