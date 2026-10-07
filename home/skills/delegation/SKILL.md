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
| "Luna can't handle code or commands, so I'll do it inline" (work machine) | It wrote and ran tests, edited manifests and reviewed diffs in testing; `read-shell` and `write-shell` run commands. Inline work burns the Claude balance. Try Luna first. |
| "I need the output to reason over anyway" | Only true if you need the raw content, not a conclusion. A sweep whose result you'll summarize or act on belongs in a sub-agent even then (see `fork` in the Agent tool). |

## Cost and speed by tier

Prices from [claude.com/pricing](https://claude.com/pricing); intelligence
index and output speed from [Artificial
Analysis](https://artificialanalysis.ai/providers/anthropic) (medium effort).
Both checked 2026-09-28 — verify current numbers before quoting them, since
this table will drift. The Haiku 5.5 row was checked 2026-10-08: price from
the Claude Code changelog, index and speed read from the Artificial Analysis
Anthropic page. The other rows' index figures date from 2026-09-28 and were
measured at medium effort unless noted, so compare Haiku 5.5's medium
figure with them:

| Tier | Input / output per MTok (million tokens) | Roughly vs. Haiku | AA intelligence index | Output tok/s |
|---|---|---|---|---|
| Haiku 5.5 (`claude-haiku-5-5`) | $0.10 / $0.50 | 1x | 34 at medium effort (29 low, 38 high, 43 max) | ~243 (max effort) |
| Haiku 4.5 (legacy) | $1 / $5 | ~10x | 15 | ~80 |
| Sonnet 5 | $2 / $10 | ~20x | 28 | ~60 |
| Opus 5.5 | $4 / $20 | ~40x | 51 (up to 58 at max effort) | ~82 |
| Fable 5.1 | $10 / $50 | ~100x | 49 (up to 53 at max effort) | ~56 |

Haiku 5.5 is the default Haiku on the Anthropic API: 1M context, and
$0.50 / $2.50 for prompts over 100K. It costs a tenth of Haiku 4.5 and scores
above Sonnet 5 on the index at medium effort (34 against 28), so the "haiku"
tier in this skill means 5.5. Anthropic positions it for classification,
extraction, routing and sub-agent tasks, and it is the first Haiku with
effort levels (default medium). Claude Code's docs list it as supported for
auto mode; Haiku 4.5 is not.

Which model `model: "haiku"` actually runs depends on the Claude Code
version. Haiku 5.5 became the default Haiku on the Anthropic API in 2.1.293;
on Bedrock, Vertex and Foundry the alias still resolves to 4.5. Before
2.1.293, which includes 2.1.286 (what was installed on 2026-10-08) and the
2.1.292 nixpkgs pinned then, expect 4.5 (inferred from the changelog, not stated by the docs). Check with
`claude --version`, and a pin via `ANTHROPIC_DEFAULT_HAIKU_MODEL` also lands
on whatever it names.

Known Haiku 5.5 weak spots, from Anthropic's prompting guide: at low or
medium effort it sometimes reports code as done without running a check, can
skip a search, and can stop early on a long agent prompt. Its safety
classifiers can return a `refusal` stop reason on benign security work. The
new tokenizer counts about 30% more tokens than Haiku 4.5 for the same text.
So ask for the check to be run and read its output.

Opus 5.5 replaced Opus 5 ($5 / $25, now listed under legacy models) and is
cheaper than it. The index shifts several points with effort/reasoning
settings, so compare tiers by rough gap, not exact integers; it also
measures benchmark reasoning, not long-running agentic work, which is where
Fable is positioned.

Haiku is the cheapest tier. Per that same pricing page, Opus's
base speed is not fast — it has an optional "fast mode" at double its own
price for roughly 2.5x the speed — and Fable is priced and positioned for
long-running agentic work, not quick bulk calls.

The gap compounds with volume: 50 haiku-tiered calls cost roughly what 2.5
sonnet-tiered ones would (Sonnet's ~20x table ratio) for work that doesn't
need sonnet's judgement — or ~1 opus-tiered one (~40x), if that's the
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
(`cheapDelegate = "copilot"`) the default is Luna through `delegate.sh`
instead; read "The per-machine ladder" below before choosing a sub-agent
tier. Step up to **sonnet** only when the
task itself — not the batch it's part of — requires judgement: picking which
of several ambiguous candidates is correct, multi-step reasoning, synthesizing
a conclusion from heterogeneous sources, or writing code whose design is still
open. Unsure which tier? Start on the cheaper one when the result can be
checked cheaply (tests, a diff, a grep), and step up if the check fails.
Pick sonnet outright only when a wrong answer would be acted on without a
check.

### The per-machine ladder

Below haiku there is a cheaper rung, and which one depends on the machine.
The Model Routing mandate in `~/.claude/CLAUDE.md` names it (nix sets it
per host through `cheapDelegate`):

| Machine | First rung | Falls back to |
|---|---|---|
| Work (`cheapDelegate = "copilot"`) | Copilot's Luna via `scripts/delegate.sh` | haiku sub-agent when credits are exhausted or the task needs MCP tools or context only this session has |
| Personal (default, `"local"`) | Local model via `scripts/delegate-to-local.sh` / `delegate-to-local-agent.sh` | haiku sub-agent when no profile is live or the task isn't haiku-shaped |

The local first rung is text in, text out (its agent mode adds read, and
optionally edit, over one directory) and runs no commands. Luna can run an
allowlisted set of commands through `delegate.sh`'s `read-shell` and
`write-shell` profiles (see [delegate-to-copilot.md](delegate-to-copilot.md)),
so on the work machine only MCP tools, anything outside those lists (`aws`,
`pup`, `kubectl apply`, `terraform plan`) go straight to a sub-agent. Needing
a Claude skill is not a reason to skip Luna: `delegate.sh` takes skill names
as its third argument and the delegate reads them.

On the work machine the Claude balance is the scarce one and Copilot's is
separate, so the default is to hand Luna the work, not to ask whether it is
worth a sub-agent. The thresholds in "When to delegate at all" (two or more
calls, spawn overhead) are for Claude sub-agents. Luna is one Bash call whose
only Claude cost is the prompt you write and the reply you read, so a single
self-contained step qualifies.

Luna-shaped work on the work machine, tried before any haiku or sonnet
sub-agent: writing or editing code from a clear spec, writing tests and
running them (`write-shell`), config and manifest edits, commit and PR text
drafts, first-pass reviews, repo and log sweeps (`read-shell`), and format
conversion. Pass the `programming` or `testing` skill by name for code work.
It sometimes misses items in a sweep, so read its result before relying on it;
raise `DELEGATE_REASONING_EFFORT` before moving up a tier. Only a wrong result
at high reasoning effort, or a task needing judgement you cannot write down,
moves it up to a sonnet sub-agent.

On a personal machine the same default applies: send local-shaped work to
the local model and the rest to a haiku sub-agent, rather than doing it
inline. Local-shaped work is text-in/text-out drafts, summaries and format
conversion, and, through `delegate-to-local-agent.sh`, reads and edits over
one directory from an exact spec (with a diff to review). A single
self-contained step qualifies; the two-call threshold is no longer the bar.
Check `list-local-profiles.sh` first; it is read-only and cheap. If no
profile is live and local-shaped work is in front of you, load one instead
of falling straight to haiku: run `switch-local-profile.sh <profile>` with
`run_in_background` (up to two minutes), give the first step to a haiku
sub-agent meanwhile, and use the local model from the next step. Load it
once and leave it loaded for the session; the switch's VRAM fit check
refuses a profile that won't fit beside a game and names one that does, so a
refusal is the signal to use haiku, not a reason to avoid trying. Don't load
for a single one-off step you could hand to haiku in the time it takes (see
[delegate-to-local.md](delegate-to-local.md)). On the work machine, a
credit-exhaustion error from `delegate.sh` is cached for 24h, so after one,
go straight to haiku for the rest of the session.

Review every result from the first rung before using it. It is weaker
(local) or external (Copilot) output, and wrong output costs more to redo
than a haiku call would have.

Haiku 5.5 ($0.10 / $0.50) now costs the same as GPT-6 Luna, the cheapest
Copilot model, so the first rung no longer wins on price alone. Its edges
are zero marginal cost (local) and, on the work machine, Copilot's separate
credit pool: Claude and Copilot are metered apart there, so keep offloading
Luna-shaped work to Luna to conserve the Claude balance for sonnet/opus
judgement work. Haiku 5.5's lower price does not change that ladder. On a
personal machine with no live local profile, or where the task needs this
session's tools or skills, a haiku sub-agent is the better choice.

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
priced at or below Haiku 5.5 and, against Haiku 4.5 on public benchmarks,
faster and more capable. Haiku 5.5 scores 34 on that index at medium effort
and runs at ~243 tok/s, so it is no longer the weaker option. Read
[delegate-to-copilot.md](delegate-to-copilot.md) for the actual numbers and
when that beats a Claude sub-agent instead of assuming Claude tiers are
always the cheaper or only option.

A third option, for zero-marginal-cost text-only work with no cloud
dependency: a model running on your own hardware via an OpenAI-compatible
endpoint. Text in, text out by default, or an agent over one directory
through `delegate-to-local-agent.sh`: read-only, or with
`LOCAL_LLM_AGENT_EDIT=1` allowed to edit there, with a diff to review before
anything is kept. It never runs commands. On ali-desktop, a 35B
mixture-of-experts model and a 9B wrote new modules, unit tests and
multi-edit changes from an exact spec, read-before-write and test-passing
(see the scorecard), and only the 27B says correctly what code does. So it
takes spec'd code, tests, drafts, summaries and extraction, not
"explain what this does", with every result reviewed by a diff or a test
run. See
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
