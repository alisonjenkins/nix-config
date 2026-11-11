---
id: "0006"
host: Alisons-MacBook-Pro
date: 2026-11-11T09:30:20Z
finding: 2026-11-02-Alisons-MacBook-Pro#1
decision: configure
reason: "claude-in-chrome and Slack tool results were 99% of the week's 638,835 tokens (337,130 and 296,966 respectively); bound Slack reads with limit/filters and reduce claude-in-chrome screenshot resolution/scale"
metric: { question: mcp-idle-servers, key: claude-in-chrome, baseline: 337130.5, unit: tokens/week }
acted_on: null
outcome: null
outcome_review: null
---
Two MCP servers accounted for almost all of the week's token volume: claude-in-chrome
(337,130 tokens / 23 calls, ~14.7k/call, screenshots) and Slack
(3e0b5c83-8e97-4100-aa03-afbcd22a6e6c, 296,966 tokens / 74 calls, ~4.0k/call, channel
reads). The 2026-11-03 review found both still growing (Slack +2.4%, and
claude_ai_Notion +41% to 46,693 tokens — new, worth folding into this same configure
pass). Reduce the Browser tool's screenshot scale/resolution where full fidelity isn't
needed, and pass `--limit`/narrower filters on Slack and Notion reads rather than
whole-channel or whole-page pulls.
