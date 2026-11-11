---
id: "0016"
host: Alisons-MacBook-Pro
date: 2026-11-11T09:30:20Z
finding: 2026-11-11-Alisons-MacBook-Pro#5
decision: dismiss
reason: "top 10 unused-skill rows total roughly 2.5k tokens/week, too small to justify the risk of trimming skill descriptions and breaking their triggering; revisit if the total grows materially"
metric: { question: skills-loaded-unused, key: dataviz, baseline: 361, unit: tokens/week }
acted_on: null
outcome: null
outcome_review: null
---
Ten skills (dataviz, claude-api, anthropic-skills:docs, anthropic-skills:pptx,
anthropic-skills:google-workspace, anthropic-skills:xlsx, anthropic-skills:docx,
code-review, artifact-capabilities, update-config) were auto-loaded with no evident use
this window, roughly 2.5k tokens/week combined across the top 10. That's small next to
this window's other findings (0012-0014) and the risk of trimming or conditionally
loading skill descriptions is breaking their triggering on a future request that does
need them — not worth it for this amount. Revisit if the combined total grows materially
or a single skill's share becomes disproportionate.
