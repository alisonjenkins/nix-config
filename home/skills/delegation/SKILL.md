---
name: delegation
description: Use before spawning any sub-agent (Agent tool), or when deciding whether a batch of similar calls belongs in the main loop at all — picks the model tier (haiku vs sonnet vs escalate), when to delegate in the first place, Explore vs general-purpose, background execution, self-contained prompts, and what must never be delegated.
---

# Delegation

The main loop runs on a fast, capable model reserved for voice, scope, and
judgement. Anything that doesn't need those three belongs on a cheaper model
in a sub-agent, not ground through inline.

## When to delegate at all

Delegate any run of ~5+ bulk calls of the same shape: `gh`/GraphQL queries,
web searches, log trawls, per-file mechanical edits, dependency-bump
enumeration. Prefer running these in the background (`run_in_background`) so
the main loop isn't blocked waiting.

Code reading stays inline: Read/Grep/Glob used to understand code you are
about to work on are cheap and belong in the main loop — never route ordinary
exploration through a sub-agent. Delegate a search sweep only when you need
the *conclusion*, not the file contents, AND it spans many files or areas you
won't otherwise open yourself.

## Picking the model: default to haiku

Default every delegated task to **haiku**. Step up to **sonnet** only when the
task itself — not the batch it's part of — requires judgement: picking which
of several ambiguous candidates is correct, multi-step reasoning across steps,
synthesizing a conclusion from heterogeneous sources, or writing/editing code.
When genuinely unsure which tier, that uncertainty is itself evidence the task
needs judgement — pick sonnet.

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
- Anything that involves writing or editing code beyond a mechanical,
  fully-specified substitution.
- Judging *which* result among several plausible ones is the right one.
- Any step whose output feeds a decision rather than a report.
- A sweep whose success criteria can't be written down completely in the
  prompt — if you can't fully specify "correct" up front, the sub-agent needs
  judgement to fill the gap, which means sonnet.

Getting the tier wrong is not symmetric. Sonnet doing haiku-shaped work merely
costs more. Haiku hitting a judgement call it can't make either produces a
wrong answer silently, or bounces back through you for a retry — which costs
more than running the whole thing on sonnet would have. When a batch mixes
trivial items with a few judgement calls, split it (haiku for the
mechanical slice, sonnet for the rest) rather than guessing which tier covers
the whole thing.

## Explore vs general-purpose

When delegating a read-only search/exploration sweep, prefer the Explore (or
Plan) sub-agent over general-purpose: Explore/Plan skip CLAUDE.md and git
status at startup, so they cost far less per spawn than a general-purpose
agent that loads the full memory hierarchy. Reach for general-purpose only
when the sweep needs tools Explore lacks (edits, writes, MCP mutations).

## Writing the prompt

- Sub-agent prompts must be self-contained: include every path, ID, query,
  and the exact output format — the sub-agent cannot see this conversation.
- Name the relevant skills in the prompt. A sub-agent gets no skill listing,
  so it cannot discover a skill on its own — but it can invoke one by exact
  name. Inject only what that task needs: "invoke the `programming` skill,
  then read its languages/rust.md" for code work, "invoke `testing`" for
  tests, and so on. Skip this for Explore/Plan sweeps, which are read-only.
- Cap the reply length explicitly (e.g. "return at most 30 lines: one line
  per PR — number, state, mergeable").

## Escalating instead of grinding

Hard problems — not high-volume ones — go the other direction: to a stronger
model via the `consult-opus` agent. See the `consulting` skill for the
trigger list and brief format. Do not confuse the two: this skill picks a
*cheaper* tier for mechanical volume; `consulting` picks a *stronger* tier for
a problem this session is stuck on. They are opposite moves and neither
substitutes for the other.

## Never delegate

User-facing judgement, irreversible actions, or work whose context cannot be
compressed into a prompt.

## Related

- `consulting`: escalating to a stronger model when stuck, not delegating
  volume to a cheaper one.
- `programming`, `testing`, `git`, and other skills: name them explicitly in
  a sub-agent prompt when the delegated task needs their guidance.
