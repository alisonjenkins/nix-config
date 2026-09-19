---
name: delegation
description: Use before spawning a sub-agent (Agent tool), deciding whether a batch of similar calls belongs in the main loop, or when a delegated result came back wrong or incomplete. Covers model tier (haiku vs sonnet), Explore vs general-purpose, background execution, self-contained prompts. Also routes to GitHub Copilot CLI delegation (`copilot`, Luna). Not for escalating to a stronger model — see `consulting`.
---

# Delegation

The main loop runs on a fast, capable model reserved for voice, scope, and
judgement. Anything that needs none of those belongs on a cheaper model in a
sub-agent, not ground through inline.

## When to delegate at all

Delegate any run of ~5+ bulk calls of the same shape: `gh`/GraphQL queries,
web searches, log trawls, per-file mechanical edits, dependency-bump
enumeration. Prefer running these in the background (`run_in_background`) so
the main loop isn't blocked waiting.

Code reading stays inline: Read/Grep/Glob to understand code you are about to
work on are cheap and belong in the main loop — never route ordinary
exploration through a sub-agent. Delegate a search sweep only when you need
the *conclusion*, not the file contents, AND it spans many files or areas you
won't otherwise open.

## Picking the model: default to haiku

Default every delegated task to **haiku**. Step up to **sonnet** only when the
task itself — not the batch it's part of — requires judgement: picking which
of several ambiguous candidates is correct, multi-step reasoning, synthesizing
a conclusion from heterogeneous sources, or writing/editing code. Unsure which
tier? That uncertainty is itself evidence the task needs judgement — pick
sonnet.

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
general-purpose agent pays for the full memory hierarchy on every spawn. Use
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

Everything above picks a *model tier* for an Agent-tool sub-agent. When the
target is GitHub Copilot's own `copilot` CLI — an external, paid delegate, not
a sub-agent — read [delegate-to-copilot.md](delegate-to-copilot.md).

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
