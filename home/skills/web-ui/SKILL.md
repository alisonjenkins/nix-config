---
name: web-ui
description: Building and testing user-facing web output — front-end design work, self-contained HTML artifacts and pages, and driving a real browser to verify a UI behaves. Use when designing or styling an interface, producing a standalone HTML page or artifact, or testing a web app end to end by clicking through it. Routes to the specialist skill that does the work.
---

# Web and UI

Each entry below is a full skill: **invoke it** rather than working from this
page.

| The ask | Invoke |
|---|---|
| Design or restyle an interface; visual and layout decisions | `/frontend-design` |
| Build a self-contained HTML page or artifact (inline CSS/JS, no external hosts) | `/web-artifacts-builder` |
| Drive a real browser to verify a web app works — clicks, forms, console errors | `/webapp-testing` |

## Availability

These leaves ship with Claude Code. In another runtime they may not be
installed — check before relying on one, and say so rather than improvising.

## Choosing

- Design first, then build: `frontend-design` decides what it should look
  like, `web-artifacts-builder` produces the shippable single file.
- `webapp-testing` is verification, not authoring — reach for it when the
  question is "does this actually work in a browser", and pair it with the
  `testing` skill's rules on what makes an assertion worth having.
- For charts and dashboards specifically, the bundled `/dataviz` skill owns
  the palette and chart-form rules; use it before writing chart code.
