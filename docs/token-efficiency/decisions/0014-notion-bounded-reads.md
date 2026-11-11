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

Guidance added: [Active mandates](../README.md#active-mandates) in this directory's
`README.md`. Left the user's global `~/.claude/CLAUDE.md` unchanged — this mandate is
scoped to this repo's own MCP connectors (Notion, Slack, claude-in-chrome), not a
general Claude Code convention like 0004's ranged-reads mandate, and a worktree session
should not be editing files outside its own working directory anyway.
