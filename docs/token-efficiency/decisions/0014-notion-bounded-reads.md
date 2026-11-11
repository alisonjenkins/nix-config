---
id: "0014"
host: Alisons-MacBook-Pro
date: 2026-11-11T00:00:00Z
finding: 2026-11-11-Alisons-MacBook-Pro#3
decision: configure
reason: "claude_ai_Notion was the single largest MCP token consumer in the 2026-11-11 digest (97,494 tokens / 45 calls, ~2.2k/call, 42% of mcp-idle-servers), ahead of Browser and Slack; extend 0006's bounded-read mandate with Notion-specific guidance"
metric: { question: mcp-idle-servers, key: claude_ai_Notion, baseline: 97494, unit: tokens/week }
acted_on: null
outcome: null
outcome_review: null
---
0006 recommended bounding Slack and Notion reads with `limit`/narrower filters instead of
whole-channel/whole-page pulls, alongside reducing claude-in-chrome screenshot
scale/resolution, but none of it had been written down as a mandate yet. The 2026-11-11
digest shows `claude_ai_Notion` has since become the largest single MCP token consumer,
making it the most urgent of the three.

Guidance added to the user's global `~/.claude/CLAUDE.md` ("Model Routing"), via
`home/programs/shared-mandates.nix` in this repo, not to a project-level doc: these MCP
connectors (Notion, Slack, claude-in-chrome) are available in every session regardless
of repo, the same category as the `0004` ranged-reads mandate, so the rule belongs
wherever every session reads it rather than only sessions working in nix-config.
[Active mandates](../README.md#active-mandates) in this directory's `README.md` cross-
references it without duplicating the text.
