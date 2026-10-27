# 0055. Hide user-typed and unused skills from the model's listing

- Status: Accepted
- Date: 2026-10-27

## Context

Every skill's name and description sit in the system prompt of every turn of a
main session. `/skill-doctor` reports that cost per skill, with the number of
model invocations over the machine's history. Reports from both machines on
2026-10-27:

| Group | Desktop tokens/turn | Laptop tokens/turn | Model invocations |
|---|---|---|---|
| claude.ai-synced skills | 3,160 | 1,140 | 2 (chrome-browser) |
| Local families and the anthropics farm | 1,310 | 3,320 | most of all use |
| superpowers plugin | 830 | 830 | regular |
| caveman and statusbar commands | 370 | 1,370 | 0 |
| speckit-init, nix-pull-build, process-todo | 150 | 300 | typed by the user |
| Total | 5,720 | 7,880 | |

The desktop already runs ADR 0038's short listing, which is why its local
families cost a third of the laptop's: the laptop host does not enable
`modules.memoryRecall`, so it installs the full descriptions.

Two groups never earn their place. Slash commands the user types (`/caveman`,
`/statusbar-theme`, `/speckit-init`) need no description in the model's
context. The claude.ai-synced skills arrive outside the Nix build; four of them
duplicate skills the farm already installs, and the model has run only
`chrome-browser`.

Claude Code's `skillOverrides` setting offers `name-only` (name stays, the
description goes) and `user-invocable-only` (the skill leaves the listing and
stays in the `/` menu). The documentation lists plugin skills as outside its
reach and gives no key form for synced skills; the only documented control for
those is `syncClaudeAiSkills = false`, which removes the whole set. A run of
`/skill-doctor` on 2.1.308 with `"anthropic-skills:morning" =
"user-invocable-only"` in a `--settings` file showed that skill leave the
listing, so the prefixed key works for synced skills too.

## Decision

In `home/programs/claude-code/default.nix`:

- `user-invocable-only` for the skills only the user starts: the six caveman
  commands, the six statusbar commands, `speckit-init`, `nix-pull-build` and
  `process-todo`. `claude-statusbar` stays listed as the router the model
  reaches when asked about the status bar.
- `name-only` for five leaves with no model invocations: `mcp-builder`,
  `slack-gif-creator`, `local-llm-setup`, `security`, `cavecrew`. Each gets a
  parent family whose description and routing table name it (`token-efficiency`,
  `documents`, `delegation`, `review`, `delegation`), so a host without ADR
  0038's recall hook still sees a trigger for it.
- `user-invocable-only` for the twelve claude.ai-synced skills the model has
  never run; `chrome-browser` stays on.

Nothing is deleted. Every hidden skill still runs from the `/` menu, and a
name-only skill still runs when the model names it.

## Consequences

- The desktop listing drops from about 5,700 to about 1,900 tokens a turn; the
  laptop from about 7,900 to about 6,200. Enabling ADR 0038's short listing on
  the laptop would take it to about 4,200, at the price of running
  `modules.memoryRecall` there.
- Skills that the model used to trigger from a description, such as
  `computer-use` or `deep-research`, now start only when the user types them.
  `/skill-doctor` will show any that should come back.
- The prefixed synced-skill key is undocumented. If a release stops honouring
  it, the synced group returns to the listing and `/skill-doctor` shows it; the
  fallback is `syncClaudeAiSkills = false`.
- Plugin skills (`superpowers:*`) stay as they are: `skillOverrides` does not
  apply to them, and the only lever is disabling the plugin.
