---
id: "0003"
host: ali-desktop
date: 2026-10-25T11:40:00Z
finding: 2026-10-25-ali-desktop#3
decision: configure
reason: "fixed context is 31.5% of each request; measure per component (MCP, settings, skills, tool schemas) before trimming"
metric: { question: fixed-context-share, key: total, baseline: 0.3153, unit: share }
acted_on: null            # commit sha or ADR once done
outcome: null             # effective | ineffective | inconclusive (set by a later review)
outcome_review: null
---
Fixed context (tool schemas, MCP, settings, skills) is about 31.5% of every request. Each component gets measured on its own before anything is removed, so the trim targets the largest real cost.
