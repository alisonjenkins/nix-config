---
name: token-efficiency
description: >-
  Use when reviewing where Claude Code spends tokens (a token or cost review,
  "what is eating my context", top tool or skill by tokens, cache hit rate,
  cc-obs-query, the observability stack digest) or when designing a tool, MCP
  server, skill or CLI so it costs fewer tokens. Not for general performance
  work or reducing a prompt by hand.
---

# Token efficiency

Two jobs, one method: find where tokens go from measured data, then design the smallest
tool that removes the waste. Status: **provisional** until a real review and the
MCP-versus-CLI experiment (spec 007, FR-038) have run; parts that rest on them are marked.

## Before anything else

The data comes from a local observability stack that a host opts into. Check it is there:

```bash
command -v cc-obs-query && cc-obs-query health
```

If `cc-obs-query` is missing or `health` fails, the stack is not enabled on this machine:
say so, and stop. Do not guess at numbers.

## Rules that hold in both jobs

- Work from the bounded views (`cc-obs-query`, the digest). Never pull raw logs or traces
  into context to "look around"; ask for a ranked summary, then drill into one item.
- A figure shown as `unavailable` is a gap in collection, not zero. Report the gap.
- Cost figures are estimates at list price. Rank by tokens first, cost second.
- Findings and decisions carry aggregates and references (tool name, session id), never
  prompt text or file contents. Decision records are committed to the repository.
- You propose; the owner decides. Do not build a tool, change settings or commit
  because a finding looks obvious.

## Routing

| Doing | Read |
|---|---|
| Running or reading a review, ranking findings, writing a decision record, comparing before and after | [review.md](review.md) |
| Designing a tool, MCP server, skill or CLI to fix a finding, or judging a design | [tool-design.md](tool-design.md) |
